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
 ┣ 📂BeamNG.drive__mods__unpacked  => junction to [My Documents]/BeamNG.drive/mods/unpacked
 ┃ ┗ 📂sir_velo
 ┃   ┗ 📂vehicles
 ┃     ┗ 📂sir_velo
 ┃       ┣ 📂lua
 ┃       ┃ ┗ 📜sim_cycling.lua     => custom vehicle script
 ┃       ┣ 📜default.png           => UI stuff
 ┃       ┣ 📜info.json             => UI stuff
 ┃       ┣ 📜materials.cs          => 3D model materials
 ┃       ┣ 📜sir_velo.jbeam        => main vehicle file
 ┃       ┗ 📜velo.dae              => exported 3D model
 ┣ 📜DummyClient.py                  => Dummy client for AntTcpCompanion
 ┣ 📜LICENSE
 ┗ 📜README.md
```
