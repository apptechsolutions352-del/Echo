#include "mpris_controller.h"

#include <algorithm>
#include <cstring>

namespace {
constexpr char kBusName[] = "org.mpris.MediaPlayer2.echo";
constexpr char kObjectPath[] = "/org/mpris/MediaPlayer2";
constexpr char kRootInterface[] = "org.mpris.MediaPlayer2";
constexpr char kPlayerInterface[] = "org.mpris.MediaPlayer2.Player";
constexpr char kChannelName[] = "org.echo.Echo/mpris";

const char kIntrospectionXml[] =
    "<node>"
    " <interface name='org.mpris.MediaPlayer2'>"
    "  <method name='Raise'/><method name='Quit'/>"
    "  <property name='CanQuit' type='b' access='read'/>"
    "  <property name='CanRaise' type='b' access='read'/>"
    "  <property name='HasTrackList' type='b' access='read'/>"
    "  <property name='Identity' type='s' access='read'/>"
    "  <property name='DesktopEntry' type='s' access='read'/>"
    "  <property name='SupportedUriSchemes' type='as' access='read'/>"
    "  <property name='SupportedMimeTypes' type='as' access='read'/>"
    " </interface>"
    " <interface name='org.mpris.MediaPlayer2.Player'>"
    "  <method name='Next'/><method name='Previous'/><method name='Pause'/>"
    "  <method name='PlayPause'/><method name='Stop'/><method name='Play'/>"
    "  <method name='Seek'><arg direction='in' type='x'/></method>"
    "  <method name='SetPosition'><arg direction='in' type='o'/><arg direction='in' type='x'/></method>"
    "  <method name='OpenUri'><arg direction='in' type='s'/></method>"
    "  <property name='PlaybackStatus' type='s' access='read'/>"
    "  <property name='LoopStatus' type='s' access='readwrite'/>"
    "  <property name='Rate' type='d' access='readwrite'/>"
    "  <property name='Shuffle' type='b' access='readwrite'/>"
    "  <property name='Metadata' type='a{sv}' access='read'/>"
    "  <property name='Volume' type='d' access='readwrite'/>"
    "  <property name='Position' type='x' access='read'/>"
    "  <property name='MinimumRate' type='d' access='read'/>"
    "  <property name='MaximumRate' type='d' access='read'/>"
    "  <property name='CanGoNext' type='b' access='read'/>"
    "  <property name='CanGoPrevious' type='b' access='read'/>"
    "  <property name='CanPlay' type='b' access='read'/>"
    "  <property name='CanPause' type='b' access='read'/>"
    "  <property name='CanSeek' type='b' access='read'/>"
    "  <property name='CanControl' type='b' access='read'/>"
    "  <signal name='Seeked'><arg type='x'/></signal>"
    " </interface>"
    "</node>";

const GDBusInterfaceVTable kVTable = {
    MprisController::on_dbus_method,
    MprisController::on_get_property,
    MprisController::on_set_property,
    {nullptr},
};

}  // namespace

MprisController::MprisController(FlView* view) {
  view_ = view;
  g_autoptr(GError) error = nullptr;
  connection_ = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (connection_ == nullptr) {
    g_warning("Echo MPRIS: cannot connect to session bus: %s", error->message);
    return;
  }

  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      connection_, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "RequestName",
      g_variant_new("(su)", kBusName, 0u), G_VARIANT_TYPE("(u)"),
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (reply == nullptr) {
    g_warning("Echo MPRIS: cannot own bus name: %s", error->message);
    return;
  }
  guint name_result = 0;
  g_variant_get(reply, "(u)", &name_result);
  owns_name_ = name_result == 1 || name_result == 4;
  if (!owns_name_) {
    g_warning("Echo MPRIS: bus name %s is already owned", kBusName);
    return;
  }

  introspection_ = g_dbus_node_info_new_for_xml(kIntrospectionXml, &error);
  if (introspection_ == nullptr) {
    g_warning("Echo MPRIS: invalid introspection data: %s", error->message);
    return;
  }
  auto* root_info = g_dbus_node_info_lookup_interface(introspection_, kRootInterface);
  auto* player_info = g_dbus_node_info_lookup_interface(introspection_, kPlayerInterface);
  root_registration_ = g_dbus_connection_register_object(
      connection_, kObjectPath, root_info, &kVTable, this, nullptr, &error);
  if (root_registration_ == 0) {
    g_warning("Echo MPRIS: cannot register root interface: %s", error->message);
    return;
  }
  player_registration_ = g_dbus_connection_register_object(
      connection_, kObjectPath, player_info, &kVTable, this, nullptr, &error);
  if (player_registration_ == 0) {
    g_warning("Echo MPRIS: cannot register player interface: %s", error->message);
    return;
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, on_method_call, this, nullptr);
  loop_status_ = g_strdup("None");
  desktop_entry_ = g_strdup("org.echo.Echo");
  playback_status_ = g_strdup("Stopped");
}

MprisController::~MprisController() {
  if (connection_ != nullptr) {
    if (player_registration_ != 0)
      g_dbus_connection_unregister_object(connection_, player_registration_);
    if (root_registration_ != 0)
      g_dbus_connection_unregister_object(connection_, root_registration_);
    if (owns_name_) {
      g_dbus_connection_call(connection_, "org.freedesktop.DBus",
                             "/org/freedesktop/DBus", "org.freedesktop.DBus",
                             "ReleaseName", g_variant_new("(s)", kBusName),
                             nullptr, G_DBUS_CALL_FLAGS_NONE, -1, nullptr,
                             nullptr, nullptr);
    }
    g_object_unref(connection_);
  }
  g_clear_object(&channel_);
  if (introspection_ != nullptr) g_dbus_node_info_unref(introspection_);
  g_free(title_);
  g_free(artist_);
  g_free(album_);
  g_free(loop_status_);
  g_free(desktop_entry_);
  g_free(playback_status_);
}

void MprisController::on_method_call(FlMethodChannel*, FlMethodCall* call,
                                     gpointer user_data) {
  auto* self = static_cast<MprisController*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_strcmp0(method, "updateMetadata") == 0 &&
      fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    auto* title = fl_value_lookup_string(args, "title");
    auto* artist = fl_value_lookup_string(args, "artist");
    auto* album = fl_value_lookup_string(args, "album");
    g_free(self->title_);
    g_free(self->artist_);
    g_free(self->album_);
    self->title_ = g_strdup(title == nullptr ? "" : fl_value_get_string(title));
    self->artist_ = g_strdup(artist == nullptr ? "" : fl_value_get_string(artist));
    self->album_ = g_strdup(album == nullptr ? "" : fl_value_get_string(album));
    self->emit_changed(kPlayerInterface, "Metadata", self->metadata_variant());
  } else if (g_strcmp0(method, "updatePlayback") == 0 &&
             fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    auto* value = fl_value_lookup_string(args, "status");
    if (value != nullptr) {
      const gchar* status = fl_value_get_string(value);
      if (g_strcmp0(status, "Playing") == 0 ||
          g_strcmp0(status, "Paused") == 0 ||
          g_strcmp0(status, "Stopped") == 0) {
        g_free(self->playback_status_);
        self->playback_status_ = g_strdup(status);
        self->emit_changed(kPlayerInterface, "PlaybackStatus",
                           g_variant_new_string(status));
      }
    }
  } else if (g_strcmp0(method, "updatePosition") == 0 &&
             fl_value_get_type(args) == FL_VALUE_TYPE_INT) {
    self->position_us_ = fl_value_get_int(args);
  } else if (g_strcmp0(method, "updateSettings") == 0 &&
             fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    auto* volume = fl_value_lookup_string(args, "volume");
    auto* shuffle = fl_value_lookup_string(args, "shuffle");
    auto* loop = fl_value_lookup_string(args, "loopStatus");
    if (volume != nullptr)
      self->volume_ = std::min(1.0, std::max(0.0, fl_value_get_float(volume)));
    if (shuffle != nullptr) self->shuffle_ = fl_value_get_bool(shuffle);
    if (loop != nullptr && self->loop_status_ != nullptr &&
        g_strcmp0(self->loop_status_, fl_value_get_string(loop)) != 0) {
      g_free(self->loop_status_);
      self->loop_status_ = g_strdup(fl_value_get_string(loop));
    }
    self->emit_changed(kPlayerInterface, "Volume", g_variant_new_double(self->volume_));
    self->emit_changed(kPlayerInterface, "Shuffle", g_variant_new_boolean(self->shuffle_));
    self->emit_changed(kPlayerInterface, "LoopStatus", g_variant_new_string(self->loop_status_));
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, fl_value_new_null(), nullptr);
}

void MprisController::on_dbus_method(GDBusConnection*, const gchar*, const gchar*,
                                     const gchar* interface_name,
                                     const gchar* method_name,
                                     GVariant* parameters,
                                     GDBusMethodInvocation* invocation,
                                     gpointer user_data) {
  auto* self = static_cast<MprisController*>(user_data);
  if (g_strcmp0(interface_name, kRootInterface) == 0) {
    if (g_strcmp0(method_name, "Raise") == 0 && self->view_ != nullptr) {
      auto* window = gtk_widget_get_toplevel(GTK_WIDGET(self->view_));
      if (GTK_IS_WINDOW(window)) gtk_window_present(GTK_WINDOW(window));
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }
  if (g_strcmp0(method_name, "Seek") == 0) {
    gint64 offset = 0;
    g_variant_get(parameters, "(x)", &offset);
    self->invoke_dart("Seek", fl_value_new_int(offset));
  } else if (g_strcmp0(method_name, "SetPosition") == 0) {
    const gchar* track_id = nullptr;
    gint64 position = 0;
    g_variant_get(parameters, "(&ox)", &track_id, &position);
    auto* args = fl_value_new_list();
    fl_value_append(args, fl_value_new_string(track_id));
    fl_value_append(args, fl_value_new_int(position));
    self->invoke_dart("SetPosition", args);
  } else if (g_strcmp0(method_name, "OpenUri") == 0) {
    const gchar* uri = nullptr;
    g_variant_get(parameters, "(&s)", &uri);
    self->invoke_dart("OpenUri", fl_value_new_string(uri));
  } else {
    self->invoke_dart(method_name);
  }
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

GVariant* MprisController::on_get_property(GDBusConnection*, const gchar*,
                                           const gchar*, const gchar* interface_name,
                                           const gchar* property_name, GError**,
                                           gpointer user_data) {
  auto* self = static_cast<MprisController*>(user_data);
  if (g_strcmp0(interface_name, kRootInterface) == 0) {
    if (g_strcmp0(property_name, "CanQuit") == 0) return g_variant_new_boolean(FALSE);
    if (g_strcmp0(property_name, "CanRaise") == 0) return g_variant_new_boolean(TRUE);
    if (g_strcmp0(property_name, "HasTrackList") == 0) return g_variant_new_boolean(FALSE);
    if (g_strcmp0(property_name, "Identity") == 0) return g_variant_new_string("Echo");
    if (g_strcmp0(property_name, "DesktopEntry") == 0)
      return g_variant_new_string(self->desktop_entry_);
    if (g_strcmp0(property_name, "SupportedUriSchemes") == 0) {
      const gchar* values[] = {"file", nullptr};
      return g_variant_new_strv(values, -1);
    }
    if (g_strcmp0(property_name, "SupportedMimeTypes") == 0) {
      const gchar* values[] = {"audio/mpeg", "audio/flac", "audio/ogg",
                               "audio/mp4", "audio/wav", nullptr};
      return g_variant_new_strv(values, -1);
    }
  } else {
    if (g_strcmp0(property_name, "PlaybackStatus") == 0)
      return g_variant_new_string(self->playback_status_);
    if (g_strcmp0(property_name, "LoopStatus") == 0)
      return g_variant_new_string(self->loop_status_);
    if (g_strcmp0(property_name, "Rate") == 0 ||
        g_strcmp0(property_name, "MinimumRate") == 0 ||
        g_strcmp0(property_name, "MaximumRate") == 0)
      return g_variant_new_double(1.0);
    if (g_strcmp0(property_name, "Shuffle") == 0)
      return g_variant_new_boolean(self->shuffle_);
    if (g_strcmp0(property_name, "Metadata") == 0)
      return self->metadata_variant();
    if (g_strcmp0(property_name, "Volume") == 0)
      return g_variant_new_double(self->volume_);
    if (g_strcmp0(property_name, "Position") == 0)
      return g_variant_new_int64(self->position_us_);
    if (g_strcmp0(property_name, "CanGoNext") == 0 ||
        g_strcmp0(property_name, "CanGoPrevious") == 0 ||
        g_strcmp0(property_name, "CanPlay") == 0 ||
        g_strcmp0(property_name, "CanControl") == 0)
      return g_variant_new_boolean(
          g_strcmp0(property_name, "CanControl") == 0 ||
          (self->title_ != nullptr && self->title_[0] != '\0'));
    if (g_strcmp0(property_name, "CanPause") == 0 ||
        g_strcmp0(property_name, "CanSeek") == 0)
      return g_variant_new_boolean(self->title_ != nullptr && self->title_[0] != '\0');
  }
  return nullptr;
}

gboolean MprisController::on_set_property(GDBusConnection*, const gchar*,
                                          const gchar*, const gchar* interface_name,
                                          const gchar* property_name, GVariant* value,
                                          GError** error, gpointer user_data) {
  auto* self = static_cast<MprisController*>(user_data);
  if (g_strcmp0(interface_name, kPlayerInterface) != 0) return FALSE;
  if (g_strcmp0(property_name, "Volume") == 0) {
    self->volume_ = std::min(1.0, std::max(0.0, g_variant_get_double(value)));
    self->invoke_dart("SetVolume", fl_value_new_float(self->volume_ * 100.0));
    self->emit_changed(kPlayerInterface, "Volume", g_variant_new_double(self->volume_));
    return TRUE;
  }
  if (g_strcmp0(property_name, "Shuffle") == 0) {
    self->shuffle_ = g_variant_get_boolean(value);
    self->invoke_dart("SetShuffle", fl_value_new_bool(self->shuffle_));
    self->emit_changed(kPlayerInterface, "Shuffle", g_variant_new_boolean(self->shuffle_));
    return TRUE;
  }
  if (g_strcmp0(property_name, "LoopStatus") == 0) {
    const gchar* loop = g_variant_get_string(value, nullptr);
    if (g_strcmp0(loop, "None") != 0 && g_strcmp0(loop, "Track") != 0 &&
        g_strcmp0(loop, "Playlist") != 0) {
      g_set_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                  "LoopStatus must be None, Track, or Playlist");
      return FALSE;
    }
    g_free(self->loop_status_);
    self->loop_status_ = g_strdup(loop);
    self->invoke_dart("SetLoopStatus", fl_value_new_string(loop));
    self->emit_changed(kPlayerInterface, "LoopStatus", g_variant_new_string(loop));
    return TRUE;
  }
  if (g_strcmp0(property_name, "Rate") == 0) {
    if (g_variant_get_double(value) != 1.0) {
      g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                  "Playback rate changes are not supported");
      return FALSE;
    }
    return TRUE;
  }
  return FALSE;
}

void MprisController::invoke_dart(const gchar* method, FlValue* arguments) {
  if (channel_ == nullptr) {
    if (arguments != nullptr) fl_value_unref(arguments);
    return;
  }
  fl_method_channel_invoke_method(channel_, method, arguments, nullptr, nullptr, nullptr);
  if (arguments != nullptr) fl_value_unref(arguments);
}

void MprisController::emit_changed(const gchar* interface_name,
                                   const gchar* property_name, GVariant* value) {
  if (connection_ == nullptr || value == nullptr) return;
  GVariantBuilder changed;
  g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&changed, "{sv}", property_name, value);
  GVariantBuilder invalidated;
  g_variant_builder_init(&invalidated, G_VARIANT_TYPE("as"));
  g_dbus_connection_emit_signal(
      connection_, nullptr, kObjectPath, "org.freedesktop.DBus.Properties",
      "PropertiesChanged",
      g_variant_new("(s@a{sv}@as)", interface_name,
                    g_variant_builder_end(&changed),
                    g_variant_builder_end(&invalidated)), nullptr);
}

GVariant* MprisController::metadata_variant() const {
  GVariantBuilder metadata;
  g_variant_builder_init(&metadata, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&metadata, "{sv}", "mpris:trackid",
                        g_variant_new_object_path("/org/mpris/MediaPlayer2/Track/1"));
  if (title_ != nullptr)
    g_variant_builder_add(&metadata, "{sv}", "xesam:title", g_variant_new_string(title_));
  if (artist_ != nullptr) {
    const gchar* artists[] = {artist_, nullptr};
    g_variant_builder_add(&metadata, "{sv}", "xesam:artist", g_variant_new_strv(artists, -1));
  }
  if (album_ != nullptr)
    g_variant_builder_add(&metadata, "{sv}", "xesam:album", g_variant_new_string(album_));
  return g_variant_builder_end(&metadata);
}
