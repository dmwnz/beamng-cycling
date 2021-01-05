# beamng-cycling

Bicycle mod for beamng.drive with control via ANT+.  

Consists of:
- Ant "Companion" middleware for communication between hardware and game
- Driveable bike vehicle


#### Project file structure
```
📦beamng-cycling
 ┣ 📂3D                              => 3D model
 ┣ 📂AntTcpCompanion                 => .NET server app for TCP IPC of relevant ANT data
 ┃ ┣ 📂Dependencies                  => Required build & runtime DLLs
 ┃ ┗ 📂Properties
 ┣ 📂BeamNG.drive__mods__unpacked    => junction to [My Documents]/BeamNG.drive/mods/unpacked
 ┃ ┗ 📂sir_velo
 ┃   ┗ 📂vehicles
 ┃     ┗ 📂sir_velo
 ┃       ┣ 📂lua
 ┃       ┃ ┗ 📜sim_cycling.lua       => custom vehicle script
 ┃       ┣ 📜default.png             => UI stuff
 ┃       ┣ 📜info.json               => UI stuff
 ┃       ┣ 📜materials.cs            => 3D model materials
 ┃       ┣ 📜sir_velo.jbeam          => main vehicle file
 ┃       ┗ 📜velo.dae                => exported 3D model
 ┣ 📜DummyClient.py                  => Dummy client for AntTcpCompanion
 ┣ 📜LICENSE
 ┗ 📜README.md
```


### Contributing

1. Clone this repo
1. Move contents of `BeamNG.drive__mods__unpacked` into `[My Documents]\BeamNG.drive\mods\unpacked` (replace `[My Documents]` with actual My Documents path)
1. Delete `BeamNG.drive__mods__unpacked` (now empty)
1. Open `cmd.exe` in repo folder
1. Type `MKLINK /J BeamNG.drive__mods__unpacked [My Documents]\BeamNG.drive\mods\unpacked` to create the folder junction
1. Done! Changes made to mod files such as `sir_velo.jbeam` will be detected by BeamNG. Reload the vehicle with `Ctrl+L`
