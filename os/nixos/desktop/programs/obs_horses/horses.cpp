#include <obs-module.h>
#include <obs-frontend-api.h>
#include <util/dstr.h>
#include <util/threading.h>
#include <QLabel>
#include <QMainWindow>
#include <QPointer>
#include <QStatusBar>
#include <QTimer>
#include <fcntl.h>
#include <unistd.h>

OBS_DECLARE_MODULE()

#define TARGET "Camera"
#define TARGET_BR "Background Removal" // the collection's own filter on TARGET, left disabled; the cutout copies its settings
#define TYPING "/run/obs-typing/typing"

static struct dstr toggle_path;
static obs_source_t *gallop, *horses, *cutout;
static obs_weak_source_t *detached_from;
static volatile bool wanted, typing, queued;
static QPointer<QLabel> status;

static bool galloping(void)
{
	return os_atomic_load_bool(&wanted) && os_atomic_load_bool(&typing);
}

static void attach(obs_source_t *target)
{
	if (!cutout) {
		obs_source_t *br = obs_source_get_filter_by_name(target, TARGET_BR);
		if (!br)
			bcrash("[horses] " TARGET " has no '" TARGET_BR "' filter to take cutout settings from");
		obs_data_t *settings = obs_source_get_settings(br);
		cutout = obs_source_create_private(obs_source_get_id(br), "Horses cutout", settings);
		obs_data_release(settings);
		obs_source_release(br);
	}
	obs_source_filter_add(target, cutout);
	obs_source_filter_add(target, horses);
}

static void detach(obs_source_t *target)
{
	obs_source_filter_remove(target, horses);
	obs_source_filter_remove(target, cutout);
}

// Keeps our filters out of the scene collection and undo snapshots: detached when the target starts saving, back as soon as anything else saves (target's filter list is serialized by then)
static void on_source_save(void *, calldata_t *cd)
{
	obs_source_t *source = (obs_source_t *)calldata_ptr(cd, "source");
	obs_source_t *target = obs_filter_get_parent(horses);
	if (source == target) {
		detach(target);
		detached_from = obs_source_get_weak_source(target);
	} else if (detached_from) {
		obs_source_t *back = obs_weak_source_get_source(detached_from);
		obs_weak_source_release(detached_from);
		detached_from = NULL;
		if (back) {
			attach(back);
			obs_source_release(back);
		}
	}
}

// for when target was the last to save; must be queued from off the UI thread, as OBS runs UI tasks queued from the UI thread synchronously
static void reconcile(void *)
{
	os_atomic_set_bool(&queued, false);
	if (obs_filter_get_parent(horses))
		return;
	obs_weak_source_release(detached_from);
	detached_from = NULL;
	obs_source_t *target = obs_get_source_by_name(TARGET);
	if (!target) // not in this scene collection
		return;
	attach(target);
	obs_source_release(target);
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
static void tick(void *, float)
{
	poll();
	obs_source_t *target = obs_filter_get_parent(horses);
	if (!target) {
		if (!os_atomic_set_bool(&queued, true))
			obs_queue_task(OBS_TASK_UI, reconcile, NULL, false);
		return;
	}
	obs_source_t *transition = obs_get_output_source(0);
	obs_source_t *program = transition ? obs_transition_get_active_source(transition) : NULL;
	// composited scenes always want the cutout; the camera-only scene keeps the real background unless horses replace it
	obs_source_set_enabled(cutout, program != target || galloping());
	obs_source_release(program);
	obs_source_release(transition);
}

static const char *get_name(void *)
{
	return "Horses";
}

static void *create(obs_data_t *, obs_source_t *self)
{
	return self;
}

static void destroy(void *) {}

static void render(void *self, gs_effect_t *)
{
	if (galloping()) {
		obs_source_t *parent = obs_filter_get_parent((obs_source_t *)self);
		gs_matrix_push();
		gs_matrix_scale3f((float)obs_source_get_base_width(parent) / (float)obs_source_get_width(gallop),
				  (float)obs_source_get_base_height(parent) / (float)obs_source_get_height(gallop), 1.0f);
		obs_source_video_render(gallop);
		gs_matrix_pop();
	}
	obs_source_skip_video_filter((obs_source_t *)self);
}

bool obs_module_load(void)
{
	const char *runtime = getenv("XDG_RUNTIME_DIR");
	if (!runtime) {
		blog(LOG_ERROR, "[horses] XDG_RUNTIME_DIR unset, nowhere to look for the toggle");
		return false;
	}
	dstr_printf(&toggle_path, "%s/obs_horses", runtime);

	obs_source_info info = {};
	info.id = "horses_filter";
	info.type = OBS_SOURCE_TYPE_FILTER;
	info.output_flags = OBS_SOURCE_VIDEO | OBS_SOURCE_CAP_DISABLED; // attached only by this plugin
	info.get_name = get_name;
	info.create = create;
	info.destroy = destroy;
	info.video_render = render;
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

	horses = obs_source_create_private("horses_filter", "Horses", NULL);
	signal_handler_connect(obs_get_signal_handler(), "source_save", on_source_save, NULL);
	obs_add_tick_callback(tick, NULL);

	// status bar rather than a dock: docks change the window layout that obs_capture syncs
	auto *window = static_cast<QMainWindow *>(obs_frontend_get_main_window());
	status = new QLabel(window);
	auto *timer = new QTimer(status);
	QObject::connect(timer, &QTimer::timeout, status, [] {
		status->setText(!os_atomic_load_bool(&wanted) ? "horses off" : galloping() ? "🐎 galloping" : "🐎 on");
	});
	timer->start(100);
	window->statusBar()->addPermanentWidget(status);
}

void obs_module_unload(void)
{
	delete status;
	obs_remove_tick_callback(tick, NULL);
	signal_handler_disconnect(obs_get_signal_handler(), "source_save", on_source_save, NULL);
	obs_source_t *target = obs_filter_get_parent(horses);
	if (target)
		detach(target);
	obs_weak_source_release(detached_from);
	obs_source_release(horses);
	obs_source_release(cutout);
	obs_source_dec_showing(gallop);
	obs_source_release(gallop);
	dstr_free(&toggle_path);
}
