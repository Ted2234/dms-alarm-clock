import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "alarmClock"

    SliderSetting {
        settingKey: "defaultMinutes"
        label: "Default Minutes"
        description: "Default countdown length"
        defaultValue: 25
        minimum: 1
        maximum: 180
        unit: " min"
    }

    ToggleSetting {
        settingKey: "showSeconds"
        label: "Show Seconds"
        description: "Display seconds in the bar"
        defaultValue: true
    }
}
