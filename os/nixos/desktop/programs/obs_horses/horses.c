#include <obs-module.h>
#include <util/dstr.h>
#include <util/threading.h>
#include <fcntl.h>
#include <unistd.h>

OBS_DECLARE_MODULE()

#define TARGET "Camera"
#define TYPING "/run/obs-typing/typing"

static struct dstr toggle_path;
static obs_source_t *gallop, *filter;
static volatile bool wanted, typing, queued;

// fires before `target` serializes its filters: keeps the filter out of the scene collection and undo snapshots
static void on_save(void *unused, calldata_t *cd)
{
	UNUSED_PARAMETER(unused);
	obs_source_t *target = calldata_ptr(cd, "source");
	signal_handler_disconnect(obs_source_get_signal_handler(target), "save", on_save, NULL);
	obs_source_filter_remove(target, filter);
}

// must be queued from off the UI thread: OBS runs UI tasks queued from the UI thread synchronously, which from `on_save` would reattach mid-save
static void reconcile(void *unused)
{
	UNUSED_PARAMETER(unused);
	os_atomic_set_bool(&queued, false);
	obs_source_t *attached = obs_filter_get_parent(filter);
	bool want = os_atomic_load_bool(&wanted);
	if (attached && !want) {
		signal_handler_disconnect(obs_source_get_signal_handler(attached), "save", on_save, NULL);
		obs_source_filter_remove(attached, filter);
	} else if (!attached && want) {
		obs_source_t *target = obs_get_source_by_name(TARGET);
		if (!target) // not in this scene collection
			return;
		obs_source_filter_add(target, filter);
		signal_handler_connect(obs_source_get_signal_handler(target), "save", on_save, NULL);
		obs_source_release(target);
	}
}

static void poll(void)
{
	bool want = access(toggle_path.array, F_OK) == 0;
	if (want) {
		char c = 0;
		int fd = open(TYPING, O_RDONLY);
		bool ok = fd >= 0 && read(fd, &c, 1) == 1 && (c == '0' || c == '1');
		if (fd >= 0)
			close(fd);
		if (ok) {
			os_atomic_set_bool(&typing, c == '1');
		} else {
			blog(LOG_ERROR, "[horses] can't read %s (obs-typing.service down?), toggling off", TYPING);
			unlink(toggle_path.array);
			want = false;
		}
	}
	os_atomic_set_bool(&wanted, want);
}

// graphics thread
static void tick(void *unused, float seconds)
{
	UNUSED_PARAMETER(unused);
	UNUSED_PARAMETER(seconds);
	poll();
	if (os_atomic_load_bool(&wanted) != (obs_filter_get_parent(filter) != NULL) && !os_atomic_set_bool(&queued, true))
		obs_queue_task(OBS_TASK_UI, reconcile, NULL, false);
}

static const char *get_name(void *unused)
{
	UNUSED_PARAMETER(unused);
	return "Horses";
}

static void *create(obs_data_t *settings, obs_source_t *self)
{
	UNUSED_PARAMETER(settings);
	return self;
}

static void destroy(void *self)
{
	UNUSED_PARAMETER(self);
}

static void render(void *self, gs_effect_t *effect)
{
	UNUSED_PARAMETER(effect);
	if (os_atomic_load_bool(&typing)) {
		obs_source_t *parent = obs_filter_get_parent(self);
		gs_matrix_push();
		gs_matrix_scale3f((float)obs_source_get_base_width(parent) / (float)obs_source_get_width(gallop),
				  (float)obs_source_get_base_height(parent) / (float)obs_source_get_height(gallop), 1.0f);
		obs_source_video_render(gallop);
		gs_matrix_pop();
	}
	obs_source_skip_video_filter(self);
}

bool obs_module_load(void)
{
	const char *runtime = getenv("XDG_RUNTIME_DIR");
	if (!runtime) {
		blog(LOG_ERROR, "[horses] XDG_RUNTIME_DIR unset, nowhere to look for the toggle");
		return false;
	}
	dstr_printf(&toggle_path, "%s/obs_horses", runtime);

	struct obs_source_info info = {
		.id = "horses_filter",
		.type = OBS_SOURCE_TYPE_FILTER,
		.output_flags = OBS_SOURCE_VIDEO | OBS_SOURCE_CAP_DISABLED, // attached only by `reconcile`
		.get_name = get_name,
		.create = create,
		.destroy = destroy,
		.video_render = render,
	};
	obs_register_source(&info);
	return true;
}

// image_source is registered by another module, so not before this
void obs_module_post_load(void)
{
	char *gif = obs_module_file("horses.gif");
	if (!gif)
		bcrash("[horses] horses.gif missing from the plugin's data dir");
	obs_data_t *settings = obs_data_create();
	obs_data_set_string(settings, "file", gif);
	gallop = obs_source_create_private("image_source", "horses gallop", settings);
	obs_data_release(settings);
	bfree(gif);
	if (!obs_source_get_width(gallop) || !obs_source_get_height(gallop))
		bcrash("[horses] image_source failed to decode horses.gif");
	obs_source_inc_showing(gallop); // image_source only advances gif frames while showing

	filter = obs_source_create_private("horses_filter", "Horses", NULL);
	obs_add_tick_callback(tick, NULL);
}

void obs_module_unload(void)
{
	obs_remove_tick_callback(tick, NULL);
	obs_source_t *attached = obs_filter_get_parent(filter);
	if (attached)
		obs_source_filter_remove(attached, filter);
	obs_source_release(filter);
	obs_source_dec_showing(gallop);
	obs_source_release(gallop);
	dstr_free(&toggle_path);
}
