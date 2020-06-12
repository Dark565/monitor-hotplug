# monitor-hotplug

Script for registering changes in monitor connections.

## Syntax
`monitor-hotplug [-hd][--help,--daemon] [--] [event-program]`

## Behavior
This program detects changes in monitor connections.  
Those changes are monitor plugin/plugout events.  
When one of them will be detected, the program will execute another program specified in 'event-program' which will handle the event.  
If event-program wasn't specified, the monitor-hotplug defaults to "monitor-hotplug-event".  
Handling program is called with arguments passed as shown below (in order from top to bottom):

- DRM card name
- Real name of that card
- DRM monitor name
- Real name of that monitor
- Monitor status (1 - just plugged, 0 - just unplugged)

## Requirements
- udevadm
- lspci
- parse-edid
- Perl >=5.14
