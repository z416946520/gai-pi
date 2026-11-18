# gai-pi memory

Durable notes the agent should keep in mind while working in this repository.

## Conventions

- GDScript only; typed variables everywhere (Godot 4.6 treats Variant inference as an error).
- Bridge classes live in `app/bridge/`, UI in `app/ui/`, pi protocol details in `ARCHITECTURE.md`.
- Every user-facing string goes through `T.t()` with a key in `app/locale/{zh,en}.json`.
- Long-running git work runs through `AsyncProcess`, never `OS.execute` on the main thread.

## Known traps

- Godot pipe reads report `ERR_FILE_EOF` spuriously; judge liveness with `OS.is_process_running`.
- `cmd.exe /c` needs the script path as its own argument (let Godot quote it).
- Effect scripts preload icons with `res://app/visuals/...`; renaming that folder breaks all 60.
