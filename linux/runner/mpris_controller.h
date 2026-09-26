#ifndef ECHO_MPRIS_CONTROLLER_H_
#define ECHO_MPRIS_CONTROLLER_H_

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

class MprisController {
 public:
  explicit MprisController(FlView* view);
  ~MprisController();

  MprisController(const MprisController&) = delete;
  MprisController& operator=(const MprisController&) = delete;

  static void on_method_call(FlMethodChannel* channel,
                             FlMethodCall* method_call,
                             gpointer user_data);
  static void on_dbus_method(GDBusConnection* connection,
                             const gchar* sender,
                             const gchar* object_path,
                             const gchar* interface_name,
                             const gchar* method_name,
                             GVariant* parameters,
                             GDBusMethodInvocation* invocation,
                             gpointer user_data);
  static GVariant* on_get_property(GDBusConnection* connection,
                                   const gchar* sender,
                                   const gchar* object_path,
                                   const gchar* interface_name,
                                   const gchar* property_name,
                                   GError** error,
                                   gpointer user_data);
  static gboolean on_set_property(GDBusConnection* connection,
                                  const gchar* sender,
                                  const gchar* object_path,
                                  const gchar* interface_name,
                                  const gchar* property_name,
                                  GVariant* value,
                                  GError** error,
                                  gpointer user_data);

 private:
  void invoke_dart(const gchar* method, FlValue* arguments = nullptr);
  void emit_changed(const gchar* interface_name,
                    const gchar* property_name,
                    GVariant* value);
  GVariant* metadata_variant() const;

  GDBusConnection* connection_ = nullptr;
  GDBusNodeInfo* introspection_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  FlView* view_ = nullptr;
  guint player_registration_ = 0;
  guint root_registration_ = 0;
  bool owns_name_ = false;
  gchar* playback_status_ = nullptr;
  bool shuffle_ = false;
  double volume_ = 0.75;
  gint64 position_us_ = 0;
  gchar* title_ = nullptr;
  gchar* artist_ = nullptr;
  gchar* album_ = nullptr;
  gchar* loop_status_ = nullptr;
  gchar* desktop_entry_ = nullptr;
};

#endif
