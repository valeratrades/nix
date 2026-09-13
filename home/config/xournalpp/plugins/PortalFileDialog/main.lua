-- xournalpp's built-in Open uses gtk_file_chooser_dialog_new, which never talks to
-- org.freedesktop.portal.FileChooser. app.getFilePath is the one entry point that
-- goes through GtkFileChooserNative, so it honours GTK_USE_PORTAL and lands in
-- termfilechooser.sh -> nvim. See upstream PR xournalpp/xournalpp#6049.

function initUi()
  app.registerUi({ menu = "Open via portal", callback = "openViaPortal", accelerator = "<Control><Shift>o" })
end

function openViaPortal()
  local path = app.getFilePath({})
  if path then
    app.openFile(path)
  end
end
