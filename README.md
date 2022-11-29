A rewrite of Stripper:Source into Sourcepawn  
It can read stripper configs with no changes necessary*  
  
*See [this issue report](https://github.com/tilgep/stripper/issues/2) for an edge case  

### **Requires at least Sourcemod 1.11.6919 for entity lump access**

Info on stripper: https://www.bailopan.net/stripper/  
Forum thread for this plugin: https://forums.alliedmods.net/showthread.php?t=339448

### Configuration
`sourcemod/configs/stripper/global_filters.cfg` for the global config  
`sourcemod/configs/stripper/maps/mapname.cfg` for map specific config

### Cvars
`stripper_file_lowercase` - Whether to load map config filenames as lower case

### Commands
`stripper_dump` - dumps all current entity properties to a file in `configs/stripper/dumps/`
