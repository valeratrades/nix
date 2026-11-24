#include <girara/log.h>
#include <librsvg/rsvg.h>
#include <zathura/plugin-api.h>

#define CSS_DPI 96.0
#define POINTS_PER_INCH 72.0

static zathura_error_t svg_document_open(zathura_document_t* document) {
  g_autoptr(GFile) file   = g_file_new_for_path(zathura_document_get_path(document));
  g_autoptr(GError) error = NULL;
  RsvgHandle* handle      = rsvg_handle_new_from_gfile_sync(file, RSVG_HANDLE_FLAGS_NONE, NULL, &error);
  if (handle == NULL) {
    girara_error("svg: %s", error->message);
    return ZATHURA_ERROR_UNKNOWN;
  }
  rsvg_handle_set_dpi(handle, CSS_DPI);

  zathura_document_set_data(document, handle);
  zathura_document_set_number_of_pages(document, 1);
  return ZATHURA_ERROR_OK;
}

static zathura_error_t svg_document_free(zathura_document_t* document, void* data) {
  zathura_document_set_data(document, NULL);
  g_clear_object((RsvgHandle**)&data);
  return ZATHURA_ERROR_OK;
}

static zathura_error_t svg_page_init(zathura_page_t* page) {
  RsvgHandle* handle = zathura_document_get_data(zathura_page_get_document(page));

  double width  = 0;
  double height = 0;
  if (!rsvg_handle_get_intrinsic_size_in_pixels(handle, &width, &height)) {
    gboolean has_viewbox   = FALSE;
    RsvgRectangle viewport = {0};
    rsvg_handle_get_intrinsic_dimensions(handle, NULL, NULL, NULL, NULL, &has_viewbox, &viewport);
    if (!has_viewbox) {
      g_autoptr(GError) error = NULL;
      if (!rsvg_handle_get_geometry_for_element(handle, NULL, NULL, &viewport, &error)) {
        girara_error("svg: %s", error->message);
        return ZATHURA_ERROR_UNKNOWN;
      }
      viewport.width += viewport.x;
      viewport.height += viewport.y;
    }
    width  = viewport.width;
    height = viewport.height;
  }
  if (!(width > 0 && height > 0)) {
    girara_error("svg: empty document");
    return ZATHURA_ERROR_UNKNOWN;
  }

  zathura_page_set_width(page, width * POINTS_PER_INCH / CSS_DPI);
  zathura_page_set_height(page, height * POINTS_PER_INCH / CSS_DPI);
  return ZATHURA_ERROR_OK;
}

static zathura_error_t svg_page_clear(zathura_page_t* UNUSED(page), void* UNUSED(data)) {
  return ZATHURA_ERROR_OK;
}

static zathura_error_t svg_page_render_cairo(zathura_page_t* page, void* UNUSED(data), cairo_t* cairo,
                                             bool UNUSED(printing)) {
  RsvgHandle* handle           = zathura_document_get_data(zathura_page_get_document(page));
  const RsvgRectangle viewport = {.width = zathura_page_get_width(page), .height = zathura_page_get_height(page)};
  g_autoptr(GError) error      = NULL;
  if (!rsvg_handle_render_document(handle, cairo, &viewport, &error)) {
    girara_error("svg: %s", error->message);
    return ZATHURA_ERROR_UNKNOWN;
  }
  return ZATHURA_ERROR_OK;
}

ZATHURA_PLUGIN_REGISTER_WITH_FUNCTIONS("svg", VERSION,
                                       ZATHURA_PLUGIN_FUNCTIONS({
                                           .document_open     = svg_document_open,
                                           .document_free     = svg_document_free,
                                           .page_init         = svg_page_init,
                                           .page_clear        = svg_page_clear,
                                           .page_render_cairo = svg_page_render_cairo,
                                       }),
                                       ZATHURA_PLUGIN_MIMETYPES({"image/svg+xml"}))
