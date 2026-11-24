#include <girara/log.h>
#include <jxl/cms.h>
#include <jxl/decode.h>
#include <jxl/thread_parallel_runner.h>
#include <zathura/plugin-api.h>

#define CSS_DPI 96.0
#define POINTS_PER_INCH 72.0

static cairo_surface_t* surface_from_rgba(const uint8_t* rgba, uint32_t width, uint32_t height) {
  cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    girara_error("jxl: %s", cairo_status_to_string(cairo_surface_status(surface)));
    cairo_surface_destroy(surface);
    return NULL;
  }

  uint8_t* data    = cairo_image_surface_get_data(surface);
  const int stride = cairo_image_surface_get_stride(surface);
  for (uint32_t y = 0; y < height; y++) {
    uint32_t* row = (uint32_t*)(data + (size_t)y * stride);
    for (uint32_t x = 0; x < width; x++, rgba += 4) {
      const uint32_t a = rgba[3];
      row[x]           = a << 24 | (rgba[0] * a + 127) / 255 << 16 | (rgba[1] * a + 127) / 255 << 8 | (rgba[2] * a + 127) / 255;
    }
  }
  cairo_surface_mark_dirty(surface);
  return surface;
}

/* first frame only */
static cairo_surface_t* decode(JxlDecoder* dec, const uint8_t* input, size_t size) {
  const JxlPixelFormat format = {.num_channels = 4, .data_type = JXL_TYPE_UINT8, .endianness = JXL_NATIVE_ENDIAN};
  JxlBasicInfo info           = {0};
  g_autofree uint8_t* rgba    = NULL;

  if (JxlDecoderSetUnpremultiplyAlpha(dec, JXL_TRUE) != JXL_DEC_SUCCESS ||
      JxlDecoderSetCms(dec, *JxlGetDefaultCms()) != JXL_DEC_SUCCESS ||
      JxlDecoderSubscribeEvents(dec, JXL_DEC_BASIC_INFO | JXL_DEC_COLOR_ENCODING | JXL_DEC_FULL_IMAGE) !=
          JXL_DEC_SUCCESS ||
      JxlDecoderSetInput(dec, input, size) != JXL_DEC_SUCCESS) {
    girara_error("jxl: decoder setup failed");
    return NULL;
  }
  JxlDecoderCloseInput(dec);

  for (;;) {
    switch (JxlDecoderProcessInput(dec)) {
    case JXL_DEC_BASIC_INFO:
      if (JxlDecoderGetBasicInfo(dec, &info) != JXL_DEC_SUCCESS) {
        girara_error("jxl: no basic info");
        return NULL;
      }
      break;
    case JXL_DEC_COLOR_ENCODING: {
      const JxlColorEncoding srgb = {.color_space       = JXL_COLOR_SPACE_RGB,
                                     .white_point       = JXL_WHITE_POINT_D65,
                                     .primaries         = JXL_PRIMARIES_SRGB,
                                     .transfer_function = JXL_TRANSFER_FUNCTION_SRGB,
                                     .rendering_intent  = JXL_RENDERING_INTENT_RELATIVE};
      if (JxlDecoderSetOutputColorProfile(dec, &srgb, NULL, 0) != JXL_DEC_SUCCESS) {
        girara_error("jxl: cannot convert to sRGB");
        return NULL;
      }
      break;
    }
    case JXL_DEC_NEED_IMAGE_OUT_BUFFER: {
      size_t length = 0;
      if (JxlDecoderImageOutBufferSize(dec, &format, &length) != JXL_DEC_SUCCESS ||
          (rgba = g_try_malloc(length)) == NULL ||
          JxlDecoderSetImageOutBuffer(dec, &format, rgba, length) != JXL_DEC_SUCCESS) {
        girara_error("jxl: cannot allocate %ux%u", info.xsize, info.ysize);
        return NULL;
      }
      break;
    }
    case JXL_DEC_FULL_IMAGE:
      return surface_from_rgba(rgba, info.xsize, info.ysize);
    default:
      girara_error("jxl: corrupt or truncated file");
      return NULL;
    }
  }
}

static zathura_error_t jxl_document_open(zathura_document_t* document) {
  g_autofree char* input  = NULL;
  size_t size             = 0;
  g_autoptr(GError) error = NULL;
  if (!g_file_get_contents(zathura_document_get_path(document), &input, &size, &error)) {
    girara_error("jxl: %s", error->message);
    return ZATHURA_ERROR_UNKNOWN;
  }

  JxlDecoder* dec = JxlDecoderCreate(NULL);
  void* runner    = JxlThreadParallelRunnerCreate(NULL, JxlThreadParallelRunnerDefaultNumWorkerThreads());
  if (dec == NULL || runner == NULL) {
    JxlDecoderDestroy(dec);
    JxlThreadParallelRunnerDestroy(runner);
    return ZATHURA_ERROR_OUT_OF_MEMORY;
  }
  cairo_surface_t* surface = NULL;
  if (JxlDecoderSetParallelRunner(dec, JxlThreadParallelRunner, runner) == JXL_DEC_SUCCESS) {
    surface = decode(dec, (const uint8_t*)input, size);
  }
  JxlDecoderDestroy(dec);
  JxlThreadParallelRunnerDestroy(runner);
  if (surface == NULL) {
    return ZATHURA_ERROR_UNKNOWN;
  }

  zathura_document_set_data(document, surface);
  zathura_document_set_number_of_pages(document, 1);
  return ZATHURA_ERROR_OK;
}

static zathura_error_t jxl_document_free(zathura_document_t* document, void* data) {
  zathura_document_set_data(document, NULL);
  cairo_surface_destroy(data);
  return ZATHURA_ERROR_OK;
}

static zathura_error_t jxl_page_init(zathura_page_t* page) {
  cairo_surface_t* surface = zathura_document_get_data(zathura_page_get_document(page));
  zathura_page_set_width(page, cairo_image_surface_get_width(surface) * POINTS_PER_INCH / CSS_DPI);
  zathura_page_set_height(page, cairo_image_surface_get_height(surface) * POINTS_PER_INCH / CSS_DPI);
  return ZATHURA_ERROR_OK;
}

static zathura_error_t jxl_page_clear(zathura_page_t* UNUSED(page), void* UNUSED(data)) {
  return ZATHURA_ERROR_OK;
}

static zathura_error_t jxl_page_render_cairo(zathura_page_t* page, void* UNUSED(data), cairo_t* cairo,
                                             bool UNUSED(printing)) {
  cairo_surface_t* surface = zathura_document_get_data(zathura_page_get_document(page));
  cairo_save(cairo);
  cairo_scale(cairo, POINTS_PER_INCH / CSS_DPI, POINTS_PER_INCH / CSS_DPI);
  cairo_set_source_surface(cairo, surface, 0, 0);
  cairo_paint(cairo);
  cairo_restore(cairo);
  return cairo_status(cairo) == CAIRO_STATUS_SUCCESS ? ZATHURA_ERROR_OK : ZATHURA_ERROR_UNKNOWN;
}

ZATHURA_PLUGIN_REGISTER_WITH_FUNCTIONS("jxl", VERSION,
                                       ZATHURA_PLUGIN_FUNCTIONS({
                                           .document_open     = jxl_document_open,
                                           .document_free     = jxl_document_free,
                                           .page_init         = jxl_page_init,
                                           .page_clear        = jxl_page_clear,
                                           .page_render_cairo = jxl_page_render_cairo,
                                       }),
                                       ZATHURA_PLUGIN_MIMETYPES({"image/jxl"}))
