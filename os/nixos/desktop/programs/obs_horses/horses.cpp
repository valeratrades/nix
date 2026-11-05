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
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <numeric>
#include <random>
#include <string>
#include <fcntl.h>
#include <unistd.h>

OBS_DECLARE_MODULE()

#define TARGET "Camera"
#define TARGET_BR "Background Removal" // the collection's own filter on TARGET; the cutout copies its settings and replaces it
#define SPEED "/run/obs-typing/speed"
#define HERD 12

// the herd gif is a 4x3 grid of 300x200 horses; each one pitches nose-down around its front hooves and dips, its tile resampled so neighbours stay put
static const char *STUMBLE_EFFECT = R"(
uniform float4x4 ViewProj;
uniform texture2d image;
uniform float4 pitch0; // radians, one herd row per uniform, one column per component
uniform float4 pitch1;
uniform float4 pitch2;
uniform float4 dip0; // px
uniform float4 dip1;
uniform float4 dip2;

sampler_state def_sampler {
	Filter = Linear;
	AddressU = Clamp;
	AddressV = Clamp;
};

struct VertInOut {
	float4 pos : POSITION;
	float2 uv : TEXCOORD0;
};

VertInOut VSDefault(VertInOut vert_in)
{
	VertInOut vert_out;
	vert_out.pos = mul(float4(vert_in.pos.xyz, 1.0), ViewProj);
	vert_out.uv = vert_in.uv;
	return vert_out;
}

float4 PSStumble(VertInOut vert_in) : TARGET
{
	float2 grid = float2(4.0, 3.0);
	float2 size = float2(300.0, 200.0);
	float2 hooves = float2(230.0, 190.0);
	float2 cell = min(floor(vert_in.uv * grid), grid - 1.0);
	float4 column = 1.0 - step(0.5, abs(float4(0.0, 1.0, 2.0, 3.0) - cell.x));
	float pitch = dot((cell.y < 0.5) ? pitch0 : ((cell.y < 1.5) ? pitch1 : pitch2), column);
	float dip = dot((cell.y < 0.5) ? dip0 : ((cell.y < 1.5) ? dip1 : dip2), column);
	float2 p = vert_in.uv * grid * size - cell * size - hooves - float2(0.0, dip);
	float c = cos(pitch);
	float s = sin(pitch);
	float2 src = clamp(hooves + float2(c * p.x + s * p.y, c * p.y - s * p.x), float2(0.5, 0.5), size - 0.5);
	return image.Sample(def_sampler, (cell * size + src) / (grid * size));
}

technique Draw
{
	pass
	{
		vertex_shader = VSDefault(vert_in);
		pixel_shader = PSStumble(vert_in);
	}
}
)";

static struct dstr toggle_path;
static gs_image_file4_t gif; // not an image_source: its playback rate isn't adjustable
static gs_effect_t *stumble_effect;
static obs_source_t *horses, *cutout;
static obs_weak_source_t *detached_from;
static volatile bool wanted, queued;
static std::atomic<float> speed;
static QPointer<QLabel> status;
// graphics thread only
static unsigned backspaces;
static float gravity;
static struct {
	float age, length, pitch, dip;
} stumbles[HERD];
static std::minstd_rand rng;

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
		char buf[64] = {};
		int fd = open(SPEED, O_RDONLY);
		ssize_t n = fd >= 0 ? read(fd, buf, sizeof(buf) - 1) : -1;
		if (fd >= 0)
			close(fd);
		float s, g;
		unsigned b;
		int used = 0;
		if (n > 0 && sscanf(buf, "%f %u %f%n", &s, &b, &g, &used) == 3 && used == n && s >= 0 && g >= 0 && g <= 1) {
			speed = s;
			backspaces = b;
			gravity = g;
		} else {
			blog(LOG_ERROR, "[horses] can't read a speed from %s (obs-typing.service down?), toggling off", SPEED);
			unlink(toggle_path.array);
			want = false;
		}
	}
	os_atomic_set_bool(&wanted, want);
}

static void stumble(void)
{
	int order[HERD];
	std::iota(order, order + HERD, 0);
	std::shuffle(order, order + HERD, rng);
	int fallers = 1 + (int)lroundf(gravity * 5);
	std::uniform_real_distribution<float> sway(0.7f, 1.0f);
	for (int i : order)
		if (fallers && stumbles[i].age >= stumbles[i].length) {
			stumbles[i] = {0, 0.4f + 0.5f * gravity, (0.08f + 0.5f * gravity) * sway(rng), 6 + 30 * gravity};
			fallers--;
		}
}

// graphics thread
static void tick(void *, float seconds)
{
	unsigned seen = backspaces;
	poll();
	for (auto &h : stumbles)
		h.age += seconds;
	if (backspaces != seen && galloping())
		stumble();
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
		vec4 pitch[3] = {}, dip[3] = {};
		for (int i = 0; i < HERD; i++) {
			auto &h = stumbles[i];
			float jolt = h.age < h.length ? sinf((float)M_PI * sqrtf(h.age / h.length)) : 0; // falls fast, recovers slower
			pitch[i / 4].ptr[i % 4] = h.pitch * jolt;
			dip[i / 4].ptr[i % 4] = h.dip * jolt;
		}
		for (int r = 0; r < 3; r++) {
			gs_effect_set_vec4(gs_effect_get_param_by_name(stumble_effect, ("pitch" + std::to_string(r)).c_str()), &pitch[r]);
			gs_effect_set_vec4(gs_effect_get_param_by_name(stumble_effect, ("dip" + std::to_string(r)).c_str()), &dip[r]);
		}
		bool srgb = gs_framebuffer_srgb_enabled();
		gs_enable_framebuffer_srgb(true);
		gs_effect_set_texture_srgb(gs_effect_get_param_by_name(stumble_effect, "image"), tex);
		while (gs_effect_loop(stumble_effect, "Draw"))
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
	if (gif.image3.image2.image.cx != 1200 || gif.image3.image2.image.cy != 600)
		bcrash("[horses] horses.gif is %ux%u, the stumble shader expects a 4x3 grid of 300x200", gif.image3.image2.image.cx, gif.image3.image2.image.cy);
	obs_enter_graphics();
	gs_image_file4_init_texture(&gif);
	char *error = NULL;
	stumble_effect = gs_effect_create(STUMBLE_EFFECT, "horses_stumble.effect", &error);
	if (!stumble_effect)
		bcrash("[horses] stumble shader: %s", error);
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
	gs_effect_destroy(stumble_effect);
	gs_image_file4_free(&gif);
	obs_leave_graphics();
	dstr_free(&toggle_path);
}
