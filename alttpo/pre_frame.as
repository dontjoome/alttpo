
// this function intercepts execution immediately before JSL MainRouting in the reset vector:
// this function is not called for every frame but is for most frames.
void on_main_loop(uint32 pc) {
  // restore our dynamic code buffer to JSL MainRouting; RTL:
  pb.restore();

  // reset ownership of OAM sprites:
  localFrameState.reset_owners();

  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;
  if (sock is null) return;

  // synchronize torches:
  update_torches();
}

// pre_frame always happens
void pre_frame() {
  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;
  if (sock is null) return;

  // backup VRAM for OAM tiles which are in-use by game:
  localFrameState.backup();

  // fetch local VRAM data for sprites:
  local.capture_sprites_vram();

  // send updated state for our Link to server:
  local.send();

  // receive network updates from remote players:
  receive();

  local.update_tilemap();

  local.update_ancillae();

  local.update_items();

  if (enableObjectSync) {
    local.update_objects();
  }

  // render remote players:
  for (uint i = 0; i < players.length(); i++) {
    auto @remote = players[i];
    if (remote is null) continue;
    if (remote is local) continue;
    if (remote.ttl <= 0) {
      remote.ttl = 0;
      continue;
    }

    remote.ttl = remote.ttl - 1;

    // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
    if (local.can_see(remote.location)) {
      // subtract BG2 offset from sprite x,y coords to get local screen coords:
      int16 rx = int16(remote.x) - local.xoffs;
      int16 ry = int16(remote.y) - local.yoffs;

      // draw remote player relative to current BG offsets:
      //message("render");
      remote.render(rx, ry);
    }
  }
}