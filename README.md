# monitor-hotplug

Script for registering changes in monitor connections.

## Syntax
`monitor-hotplug.pl [--help|-h] [--] [action-program]`

## Behavior
When this script detects a change in a monitor connection, it executes 'action-program' specified in the argument.  
If action-program wasn't specified, the script defaults to "hotplug-action".  
Program is called as in example:  
`action-program card0 "Intel HD 610" card0-HDMI-A-1 "Asus" 1`.

- card0 - DRM card name
- "Intel HD 610" - Real name of that card
- card0-HDMI-A-1 - DRM monitor name
- "Asus" - Real name of that monitor
- 1 - Monitor status (1 - just plugged, 0 - just unplugged)

## Requirements
- udevadm
- lspci
- parse-edid
- Perl >=5.14
