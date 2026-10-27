#include <obs-module.h>
#include <obs-frontend-api.h>
#include <graphics/image-file.h>
#include <util/dstr.h>
#include <util/threading.h>
#include <QLabel>
#include <QMainWindow>
#include <QPointer>
#include <QStatusBar>
#include <QTimer>
#include <atomic>
#include <cstdlib>
#include <fcntl.h>
#include <unistd.h>

OBS_DECLARE_MODULE()

#define TARGET "Camera"
#define TARGET_BR "Background Removal" // the collection's own filter on TARGET; the cutout copies its settings and replaces it
#define SPEED "/run/obs-typing/speed"

static struct dstr toggle_path;
static gs_image_file4_t gif; // not an image_source: its playback rate isn't adjustable
static obs_source_t *horses, *cutout;
static obs_weak_source_t *detached_from;
static volatile bool wanted, queued;
static std::atomic<float> speed;
static QPointer<QLabel> status;

static bool galloping(void)
{
	return os_atomic_load_bool(&wanted) && speed > 0;
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
		obs_source_set_enabled(br, false); // would cut out the camera-only scene too
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
		char buf[16] = {};
		int fd = open(SPEED, O_RDONLY);
		ssize_t n = fd >= 0 ? read(fd, buf, sizeof(buf) - 1) : -1;
		if (fd >= 0)
			close(fd);
		char *end = buf;
		float s = n > 0 ? strtof(buf, &end) : -1;
		if (n > 0 && end == buf + n && s >= 0) {
			speed = s;
		} else {
			blog(LOG_ERROR, "[horses] can't read a speed from %s (obs-typing.service down?), toggling off", SPEED);
			unlink(toggle_path.array);
			want = false;
		}
	}
	os_atomic_set_bool(&wanted, want);
}

// graphics thread
static void tick(void *, float seconds)
{
	poll();
	if (galloping() && gs_image_file4_tick(&gif, (uint64_t)(seconds * speed * 1e9f))) {
		obs_enter_graphics();
		gs_image_file4_update_texture(&gif);
		obs_leave_graphics();
	}
	obs_source_t *target = obs_filter_get_parent(horses);
	if (!target) {
		if (!os_atomic_set_bool(&queued, true))
			obs_queue_task(OBS_TASK_UI, reconcile, NULL, false);
		return;
	}
	obs_source_t *transition = obs_get_output_source(0);
	obs_source_t *program = transition ? obs_transition_get_active_source(transition) : NULL;
	// composited scenes cut the room out so it doesn't cover the screen; the camera-only scene keeps it, horses only around the camera
	obs_source_set_enabled(cutout, program != target);
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
		gs_texture_t *tex = gif.image3.image2.image.texture;
		gs_effect_t *effect = obs_get_base_effect(OBS_EFFECT_DEFAULT);
		bool srgb = gs_framebuffer_srgb_enabled();
		gs_enable_framebuffer_srgb(true);
		gs_effect_set_texture_srgb(gs_effect_get_param_by_name(effect, "image"), tex);
		while (gs_effect_loop(effect, "Draw"))
			gs_draw_sprite(tex, 0, obs_source_get_base_width(parent), obs_source_get_base_height(parent));
		gs_enable_framebuffer_srgb(srgb);
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

void obs_module_post_load(void)
{
	char *path = obs_module_file("horses.gif");
	if (!path)
		bcrash("[horses] horses.gif missing from the plugin's data dir");
	gs_image_file4_init(&gif, path, GS_IMAGE_ALPHA_PREMULTIPLY_SRGB);
	bfree(path);
	if (!gif.image3.image2.image.loaded)
		bcrash("[horses] failed to decode horses.gif");
	obs_enter_graphics();
	gs_image_file4_init_texture(&gif);
	obs_leave_graphics();

	horses = obs_source_create_private("horses_filter", "Horses", NULL);
	signal_handler_connect(obs_get_signal_handler(), "source_save", on_source_save, NULL);
	obs_add_tick_callback(tick, NULL);

	// status bar rather than a dock: docks change the window layout that obs_capture syncs
	auto *window = static_cast<QMainWindow *>(obs_frontend_get_main_window());
	status = new QLabel(window);
	auto *timer = new QTimer(status);
	QObject::connect(timer, &QTimer::timeout, status, [] {
		status->setText(!os_atomic_load_bool(&wanted) ? "horses off"
				: galloping()                    ? QString("🐎 galloping ×%1").arg(speed.load(), 0, 'f', 1)
								 : "🐎 on");
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
	obs_enter_graphics();
	gs_image_file4_free(&gif);
	obs_leave_graphics();
	dstr_free(&toggle_path);
}
