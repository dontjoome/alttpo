
// this function intercepts execution immediately before JSL MainRouting in the reset vector:
// this function is not called for every frame but is for most frames.
// when it is called, this function is always called before pre_frame.
void on_main_loop(uint32 pc) {
  //message("main");

  // restore our dynamic code buffer to JSL MainRouting; RTL:
  pb.restore();

  if (!enableRenderToExtra) {
    // reset ownership of OAM sprites:
    localFrameState.reset_owners();
  }

  local.fetch();

  if (settings.SyncTunic) {
    local.update_palette();
  }

  if (!enableRenderToExtra) {
    // backup VRAM for OAM tiles which are in-use by game:
    localFrameState.backup();
  }

  // fetch local VRAM data for sprites:
  local.capture_sprites_vram();

  if (settings.started && !(sock is null)) {
    // send updated state for our Link to server:
    local.send();

    // receive network updates from remote players:
    receive();
  }

  local.update_tilemap();

  local.update_ancillae();

  local.update_items();

  local.update_overworld();

  local.update_rooms();

  if (enableObjectSync) {
    local.update_objects();
  }

  // synchronize torches:
  update_torches();

  if (pb.offset > 0) {
    // end the patch buffer:
    pb.jsl(rom.fn_main_routing);  // JSL MainRouting
    pb.rtl();                     // RTL
  }
}

// pre_frame always happens
void pre_frame() {
  //message("pre_frame");

  if (enableRenderToExtra) {
    ppu::extra.count = 0;
    ppu::extra.text_outline = true;
    ppu::extra.font_name = settings.FontName;
  }

  // don't render players or labels in pre-game modules:
  if (local.module < 0x05) return;

  // render remote players:
  int ei = 0;
  for (uint i = 0; i < players.length(); i++) {
    auto @remote = players[i];
    if (remote is null) continue;
    if (remote is local) continue;
    if (remote.ttl <= 0) {
      remote.ttl = 0;
      continue;
    }

    if (remote.ttl > 0) {
      remote.ttl = remote.ttl - 1;
    }

    // don't render on in-game map:
    if (local.module == 0x0e && local.sub_module == 0x07) continue;

    // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
    if (local.can_see(remote.location)) {
      // calculate screen scroll offset between both players to adjust OAM sprite x,y coords:
      int rx = int(remote.xoffs - local.xoffs);
      int ry = int(remote.yoffs - local.yoffs);

      // draw remote player relative to current BG offsets:
      if (enableRenderToExtra) {
        ei = remote.renderToExtra(rx, ry, ei);

        if (settings.ShowLabels) {
          ei = remote.renderLabel(rx, ry, ei);
        }
      } else {
        remote.renderToPPU(rx, ry);
      }
    }
  }

  if (settings.ShowMyLabel) {
    ei = local.renderLabel(0, 0, ei);
  }

  if (enableRenderToExtra) {
    ppu::extra.count = ei;
  }
}