architecture wdc65816
endian lsb

// patch over header values to extend ROM size from 8Mb to 16Mb:
{
    //origin 0x007FC0 // <- 7FC0 - Bank00.asm : 9173 (db "THE LEGEND OF ZELDA  " ; 21 bytes)
    //db $23, $4E

    origin 0x007FD5 // <- 7FD5 - Bank00.asm : 9175 (db $20   ; rom layout)
    //db #$35 // set fast exhirom
    db $30 // set fast lorom

    //origin 0x007FD6 // <- 7FD6 - Bank00.asm : 9176 (db $02   ; cartridge type)
    //db $55 // enable S-RTC

    origin 0x007FD7 // <- 7FD7 - Bank00.asm : 9177 (db $0A   ; rom size)
    db $0B // mark rom as 16mbit

    //origin 0x007FD8 // <- 7FD8 - Bank00.asm : 9178 (db $03   ; ram size (sram size))
    //db $05 // mark sram as 32k

    origin 0x1FFFFF // <- 1FFFFF
    db $00 // expand file to 2mb
}

// Main loop hook:
origin 0x00005D
base   0x00805D
    jml mainLoopHook

origin 0x000034
base   0x008034
mainLoopReturn:;

// Post-NMI hook:
origin 0x00021B
base   0x00821B
    jml nmiPostHook

origin 0x000220
base   0x008220
nmiPostReturn:;

// our NMI hook:
origin 0x100000
base   0xA08000

/////////////////////////////////////////////////////////////////////////////

constant pkt.feef = 0           // [2]
constant pkt.size = 2           // [2]
constant pkt.version = 4        // [2]
constant pkt.module = 6         // [1]
constant pkt.sub_module = 7     // [1]
constant pkt.world = 8          // [1]
constant pkt.room = 9           // [2]
constant pkt.x = 11             // [2]
constant pkt.y = 13             // [2]
constant pkt.z = 15             // [2]
constant pkt.xoffs = 17         // [2]
constant pkt.yoffs = 19         // [2]
constant pkt.sword = 21         // [1]
constant pkt.shield = 22        // [1]
constant pkt.armor = 23         // [1]
constant pkt.dma7E_table = 24   // [12]
constant pkt.dma10_table = 36   // [12]

// Each OAM sprite is 4 bytes:
// [0]: xxxxxxxx X coordinate on screen in pixels. This is the lower 8 bits.
// [1]: yyyyyyyy Y coordinate on screen in pixels.
// [2]: cccccccc Character number to use. This is the lower 8 bits. See [3]
// [3]: vhoopppc
//   v - vertical flip
//   h - horizontal flip
//   o - priority bits (0-3)
//   p - palette (0-7)
//   c - the 9th (and most significant) bit of the character number for this sprite.
constant pkt.oam_count = 48
constant pkt.oam_table = 49
constant pkt.oam_table.0 = pkt.oam_table+0
constant pkt.oam_table.1 = pkt.oam_table+1
constant pkt.oam_table.2 = pkt.oam_table+2
constant pkt.oam_table.3 = pkt.oam_table+3
constant oam_max_count = 32
constant oam_entry_size = 4
// Extended table (5th byte of each OAM sprite in separate table):
// [0]: ------sx
//   x - 9th bit of X coordinate
//   s - size toggle bit
constant pkt.oam_table_ext = pkt.oam_table + (oam_max_count * oam_entry_size)
constant pkt.oam_table_ext.0 = pkt.oam_table_ext
constant pkt.total_size = pkt.oam_table_ext + (oam_max_count * 1)

/////////////////////////////////////////////////////////////////////////////

constant bank = $7F
constant free_ram_addr = $7667

// scratch space
constant scratch = free_ram_addr
constant tmp_oam_size = 0

// local packet addr
constant local = $7700
// remote packet addr
constant remote = $8200

expression addr(base, offs) = base + offs
expression long(base, offs) = (bank << 16) + base + offs

/////////////////////////////////////////////////////////////////////////////

expected_packet_size:
    dw pkt.total_size   // $A08000
supported_packet_version:
    dw 0                // $A08002

mainLoopHook:
    // our JML hook call replaced this code:
    //   STZ $12
    //   BRA .nmi_wait_loop     // aka $008034

    phb
    rep #$20

    // Sets DP to $0000
    //lda.w #$0000 ; tcd

    // $7EC84A[0x1FB6] - seemingly free ram (nearly 8K!)
    // $7F7667[0x6719] = free RAM!

    sep #$30                        // 8-bit m,a,x,y

    // $7E0011 = sub-module
    lda $11
    sta.l long(local, pkt.sub_module)
    // $7E0010 = main module
    lda $10
    sta.l long(local, pkt.module)

    cmp #$07 ; beq validModule      // $07 is dungeon
    cmp #$09 ; beq validModule      // overworld
    cmp #$0b ; beq validModule      // overworld special (master sword area)
    cmp #$0e ; beq validModule      // dialogue/monologue or inventory menu
    cmp #$0f ; beq validModule      // close spotlight
    cmp #$10 ; beq validModule      // open spotlight
invalidModule:
    // not a good time to sync state:
    jmp mainLoopHookDone

validModule:
    // sep #$30    //  8-bit m,a,x,y

    // build local packet to send to remote players:
    lda $0FFF       // in dark world = $01, else $00
    asl
    ora $1B         // in dungeon = $01, else $00
    sta.l long(local, pkt.world)
    // if in dungeon, use dungeon room value:
    and #$01
    beq overworld   // if dungeon == 0, load overworld room number:

    // load dungeon room number as word:
    rep #$30        // 16-bit m,a,x,y
    lda $A0
    sta.l long(local, pkt.room)
    bra coords
overworld: // load overworld room number as word:
    rep #$30        // 16-bit m,a,x,y
    lda $8A
    sta.l long(local, pkt.room)

coords:
    // load X, Y, Z coords:
    lda $22
    sta.l long(local, pkt.x)
    lda $20
    sta.l long(local, pkt.y)
    lda $24
    sta.l long(local, pkt.z)

    // xoffs = int16(bus::read_u16(0x7E00E2, 0x7E00E3)) - int16(bus::read_u16(0x7E011A, 0x7E011B));
    lda $E2
    clc
    sbc $011A
    sta.l long(local, pkt.xoffs)
    // yoffs = int16(bus::read_u16(0x7E00E8, 0x7E00E9)) - int16(bus::read_u16(0x7E011C, 0x7E011D));
    lda $E8
    clc
    sbc $011C
    sta.l long(local, pkt.yoffs)

    // sword, shield, armor
    sep #$20    //  8-bit m,a
    lda $F359
    sta.l long(local, pkt.sword)
    lda $F35A
    sta.l long(local, pkt.shield)
    lda $F35B
    sta.l long(local, pkt.armor)
    rep #$20        // 16-bit m,a

    // DMA source addresses for bank $7E (decompressed sprites in WRAM) and $10 (ROM):
    phb
    lda.w #23                           // 24 bytes (12 words) to copy
    ldx.w #$0AC0                        // from $7E0AC0
    ldy.w #addr(local, pkt.dma7E_table) // to   $7Fxxxx where xxxx is dma7E_table addr
    mvn $7F=$7E                         // move bytes from bank $7E to $7F
    plb

sprites:
    // rep #$30     // 16-bit m,a,x,y

    // $0352 = OAM index where Link sprites were written to
    constant link_oam_start = $0352

    lda.w #$0000

    // local.oam_count = #$00
    rep #$10        // 16-bit x,y
    sep #$20        //  8-bit m,a
    sta.l long(local, pkt.oam_count)

    // X is our index into local packet OAM table (array index, not byte index):
    // X = 0
    ldx.w #$0000

    // jump back to $0C OAM index and find sprites to sync:
    function spark_loop {
        sep #$20        //  8-bit m,a
        rep #$10        // 16-bit x,y

        // leave X alone; it is our current local packet OAM write index.
        ldy.w #($000C << 2)     // start at WRAM OAM index $0C

    loop:
        cpy.w #($0012 << 2)     // stop at index $12 inclusive
        bcs break

        lda $0801,y                 // read Y coordinate
        cmp #$f0 ; beq continue     // skip if $F0

        lda $0803,y             // read CHR.9
        and #$01
        bne continue            // skip if 9th bit of CHR is high (second page of sprite VRAM)

        lda $0802,y             // read CHR

        // sword charge and spin attack sparkles:
        cmp #$80 ; beq sync
        cmp #$83 ; beq sync
        cmp #$b7 ; beq sync
        cmp #$92 ; beq sync
        cmp #$8c ; beq sync
        cmp #$d6 ; beq sync
        cmp #$93 ; beq sync
        cmp #$d7 ; beq sync

        // sword clinks on solid tile:
        cmp #$b9 ; beq sync
        cmp #$90 ; beq sync
        //cmp #$92 ; beq sync  // already included above

        // picked up items:
        cmp #$42 ; beq sync    // sign
        cmp #$24 ; beq sync    // room-specific item (mushroom, powder, etc.)
        cmp #$44 ; beq sync    // stone
        cmp #$46 ; beq sync    // bush
        cmp #$4A ; beq sync    // big stone
        cmp #$5e ; beq sync    // fish (left)
        cmp #$5f ; beq sync    // fish (right)

        jmp part2

    sync:
        jsr copy_oam_sprite
        inx

    continue:
        iny #4
        jmp loop

    break:
        jmp break2

    part2:
        // rubble:
        cmp #$48 ; beq sync2
        cmp #$49 ; beq sync2
        cmp #$58 ; beq sync2
        cmp #$59 ; beq sync2
        cmp #$4e ; beq sync2
        cmp #$4f ; beq sync2

        // mirror dust:
        cmp #$4c ; beq sync2
        cmp #$4d ; beq sync2
        cmp #$5c ; beq sync2
        cmp #$5d ; beq sync2

        // boomerang:
        cmp #$26 ; beq sync2    // boomerang itself
        //cmp #$80 ; beq sync2  // first    tink
        //cmp #$92 ; beq sync2  // second   tink
        cmp #$81 ; beq sync2    // X cross  tink
        cmp #$82 ; beq sync2    // circular thick tink
        //cmp #$93 ; beq sync2  // circular light tink

        // lantern fire:
        cmp #$e3 ; beq sync2
        cmp #$f3 ; beq sync2
        cmp #$a4 ; beq sync2
        cmp #$a5 ; beq sync2
        cmp #$b2 ; beq sync2
        cmp #$b3 ; beq sync2
        cmp #$9c ; beq sync2    // tiny flame dot; reused by ghost in graveyard?

        bra continue2

    sync2:
        jsr copy_oam_sprite
        inx

    continue2:
        iny #4
        jmp loop

    break2:
    }

    function link_body_loop {
        // Y is our index into tmp OAM (multiple of 4 bytes):
        // Y = link_oam_start
        ldy.w link_oam_start

    loop:
        // A = oam[y].b1
        lda $0801,y

        // if (A == $f0) continue; // sprite is off screen
        cmp #$f0
        beq continue

        // copy WRAM OAM entry to local data packet:
        jsr copy_oam_sprite

        // X++
        inx
        // if (X >= oam_max_count) break;
        cpx.w #oam_max_count
        bcs break

    continue:
        // y += 4
        iny #4

        rep #$20        // 16-bit m,a
        // if ((y - link_oam_start) < $0030) goto sprloop;
        tya
        clc
        sbc.w link_oam_start
        cmp.w #$0030    // number of OAM bytes that are reserved for Link body
        sep #$20        //  8-bit m,a
        bcc loop
    break:
    }

    // local.oam_count = X
    sep #$20            //  8-bit m,a
    txa
    sta.l long(local, pkt.oam_count)

    jmp finalize_local_packet

// copy OAM sprite into table:
function copy_oam_sprite {
    // X = unscaled index into local packet OAM table
    // Y =   scaled index into WRAM OAM table
    // A clobbered
    php

    // store unscaled X
    phx

    // X = X << 2
    {
        rep #$20        // 16-bit m,a
        txa
        asl #2
        tax
        sep #$20        //  8-bit m,a
    }

    // copy oam.b0 into local.oam_table[x].b0:
    lda $0800,y
    sta.l long(local, pkt.oam_table.0),x
    // copy oam.b1 into local.oam_table[x].b1:
    lda $0801,y
    sta.l long(local, pkt.oam_table.1),x
    // copy oam.b2 into local.oam_table[x].b2:
    lda $0802,y
    sta.l long(local, pkt.oam_table.2),x
    // copy oam.b3 into local.oam_table[x].b3:
    lda $0803,y
    sta.l long(local, pkt.oam_table.3),x

    // restore unscaled X
    plx

    // load extra bits from extended table:
    phy

    // Y = Y >> 2
    {
        rep #$20        // 16-bit m,a
        tya
        lsr
        lsr
        tay
        sep #$20        //  8-bit m,a

        // luckily for us, $0A20 through $0A9F contain each sprite's extra 2-bits at byte boundaries and are not compacted
        lda $0A20,y
        sta.l long(local, pkt.oam_table_ext.0),x
    }

    ply

    plp

    rts
}

finalize_local_packet:
    // finalize local data packet:
    rep #$20
    lda.w #$feef
    sta.l long(local, pkt.feef)
    lda.l expected_packet_size
    sta.l long(local, pkt.size)
    lda.l supported_packet_version
    sta.l long(local, pkt.version)

    // attempt to render remote player into local OAM:
renderRemote:
    // if (remote.location != local.location) return;
    // rep #$20
    lda.l long(remote, pkt.room)
    cmp   long(local, pkt.room)
    bne mainLoopHookDone
    sep #$20        //  8-bit m,a
    lda.l long(remote, pkt.world)
    cmp   long(local, pkt.world)
    bne mainLoopHookDone
    jmp renderRemoteOAM

mainLoopHookDone:
    sep #$30

    ldy.b #$1C
    plb

    // copied from Main_PrepSpritesForNmi
buildHighOamTable:
    // Y = 0x1C, X = 0x70
    tya ; asl #2 ; tax

    // Start at $0A93?
    lda $0A23,x ; asl #2
    ora $0A22,x ; asl #2
    ora $0A21,x ; asl #2
    ora $0A20,x ; sta $0A00,y

    lda $0A27,x ; asl #2
    ora $0A26,x ; asl #2
    ora $0A25,x ; asl #2
    ora $0A24,x ; sta $0A01,y

    lda $0A2B,x ; asl #2
    ora $0A2A,x ; asl #2
    ora $0A29,x ; asl #2
    ora $0A28,x ; sta $0A02,y

    lda $0A2F,x ; asl #2
    ora $0A2E,x ; asl #2
    ora $0A2D,x ; asl #2
    ora $0A2C,x ; sta $0A03,y

    dey #4 ; bpl buildHighOamTable

    // execute code we replace with JML hook:
    stz $12
    jml mainLoopReturn

exitLoop:
    jmp mainLoopHookDone

renderRemoteOAM:
    // clear A
    rep #$20
    lda.w #$0000
    sep #$20

    // loop through each remote OAM item:
    {
        ldx.w #$0000            // X is our remote OAM table index (multiple of 1)
        rep #$20
        lda.w link_oam_start    // Y is our  local OAM slot index (multiple of 4)
        clc
        adc #$0C
        tay
        sep #$20
        // TODO: get remote sprite OAM index values and move them into close-enough spots in local OAM table
    forEachRemoteOAM:
        // if (X >= oam_count) break;
        rep #$20
        txa
        sep #$20
        cmp.l long(remote, pkt.oam_count)
        bcs exitLoop

        // local and remote player are in same location:
        // check local OAM table for free slots
        {
        findEmptyOAM:
            // advance local OAM pointer:
            rep #$20        // 16-bit m,a
            // if ((y - link_oam_start) < $30) break;
            tya
            clc
            cmp.w #$0200
            sep #$20        //  8-bit m,a
            bcs exitLoop

            // Load Y coord from local OAM:
            lda $0801,y

            // check if sprite slot is free
            // if (oam.y == $f0) goto foundEmptyOAM;
            cmp #$f0
            beq foundEmptyOAM

            // y += 4
            iny #4
            // continue;
            jmp findEmptyOAM

        foundEmptyOAM:
            // copy over OAM attributes from remote:

            // load extra table bits (------sx):
            lda.l long(remote, pkt.oam_table_ext.0),x
            // BA = AB
            xba // swap lo and hi bytes
            rep #$20
            // xbit9 = (BA & 0x0100)
            and.w #$0100
            sta.l long(scratch, 0)
            sep #$20

            // store unscaled X:
            phx

            bra useSprite
        skipSprite:
            plx
            jmp forEachRemoteOAMContinue
        useSprite:

            // X = X << 2
            rep #$20
            txa
            asl #2
            tax
            sep #$20

            // attributes:
            lda long(remote, pkt.oam_table.3),x
            sta $0803,y

            // X coord
            lda long(remote, pkt.oam_table.0),x
            rep #$20
            // A = A | xbit9
            ora.l long(scratch, 0)
            // A = A + (remote.xoffs - local.xoffs)
            and #$00ff
            clc
            adc long(remote, pkt.xoffs)
            sec
            sbc long(local, pkt.xoffs)
            // if (A < -32) continue;
            cmp #$ffe0  // -32
            bcs +
            // if (A >= 0xFF) continue;
            cmp #$00ff
            bcs skipSprite
         +; // transfer 9th bit to extra table
            pha
            {
                // isolate 9th bit
                and #$0100
                // xbit9 = (A & 0x0100)
                sta.l long(scratch, 0)
            }
            pla

            sep #$20
            sta $0800,y

            // Y coord
            lda long(remote, pkt.oam_table.1),x
            rep #$20
            // A = A + (remote.yoffs - local.yoffs)
            and #$00ff
            clc
            adc long(remote, pkt.yoffs)
            sec
            sbc long(local, pkt.yoffs)
            // if (A < -32) continue;
            cmp #$ffe0  // -32
            bcs +
            // if (A >= 0xF0) continue;
            cmp #$00f0
            bcs skipSprite
         +; sep #$20
            sta $0801,y

            // oam[2] is chr, need to remap to new sprite locations:
            lda long(remote, pkt.oam_table.2),x

            bit #$EC    // $00..$03,$10..$13 -> $CB..$CE,$DB..$DE
            bne +
            clc
            adc #$CB
            bra emitChr
         +; bit #$EB    // $04,$14 -> $40,$50
            bne +
            clc
            adc #$3C
            bra emitChr
         +; cmp #$20    // if (A >= $20) continue;
            bcs emitChr
            // A = A - 5
            sec
            sbc #$05
            // if (A & $EC)
            bit #$EC    // $05..$08,$15..$18 -> $64..$67,$74..$77
            bne +       // if A >= $09 skip
            clc
            adc #$64
            bra emitChr
         +; clc
            adc #$05
        emitChr:
            sta $0802,y

            // restore unscaled X
            plx

            // read extended OAM table:
            phy

            // Y = Y >> 2
            rep #$20
            tya
            lsr #2
            tay
            sep #$20

            lda.l long(remote, pkt.oam_table_ext.0),x
            rep #$20
            and #$00ff
            xba
            ora.l long(scratch, 0)
            xba
            sep #$20
            sta $0A20,y

            ply

            // y += 4
            iny #4
        }
    forEachRemoteOAMContinue:
        // x++
        inx
        jmp forEachRemoteOAM
    forEachRemoteOAMDone:
    }

    jmp mainLoopHookDone


// Runs after main NMI routine has completed, i.e. after all DMA writes to VRAM, OAM, and CGRAM.
nmiPostHook:
    sep #$30    // 8-bit m,a,x,y

    lda $10                             // $7E0010 = main module
    cmp #$07 ; beq nmiPostValidModule   // dungeon
    cmp #$09 ; beq nmiPostValidModule   // overworld
    cmp #$0b ; beq nmiPostValidModule   // overworld special (master sword area)
    cmp #$0e ; beq nmiPostValidModule   // dialogue/monologue or inventory menu
    cmp #$0f ; beq nmiPostValidModule   // close spotlight
    cmp #$10 ; beq nmiPostValidModule   // open spotlight
nmiPostInvalidModule:
    // not a good time to sync state:
nmiPostHookDone2:
    sep #$30

    // This is the code our hook JML instruction replaced so we must run it here:
    lda.b $13 ; sta $2100

    // Jump back to the instruction after our JML interception:
    jml nmiPostReturn

nmiPostValidModule:
    rep #$20    // m,a to 16-bit

    // check remote packet signature:
    lda.l long(remote, pkt.feef)
    cmp.w #$feef
    bne nmiPostHookDone2

    lda.l long(remote, pkt.size)
    cmp.l expected_packet_size
    bne nmiPostHookDone2

    lda.l long(remote, pkt.version)
    cmp.l supported_packet_version
    bne nmiPostHookDone2

    // if (remote.location != local.location) return;
    // rep #$20
    lda.l long(remote, pkt.room)
    cmp.l long(local, pkt.room)
    bne nmiPostHookDone2
    sep #$20        //  8-bit m,a
    lda.l long(remote, pkt.world)
    cmp.l long(local, pkt.world)
    rep #$20
    bne nmiPostHookDone2

    // TODO: consider a time-to-live counter on remote packet to increment in the case
    // remote updates don't come through.

    // We still need DMA to transfer remote player's sprites into VRAM. Remote player's
    // packet could just refer to local player's ROM addresses for sprites. This would
    // mean the local player would not see remote player's customized sprites. Although,
    // this could be made possible if customized sprite data were exchanged before gameplay
    // and included in extra ROM space in this romhack; we added an extra 1MB after all.
    // Going further with this idea, perhaps all known customized sprite sets could be
    // included in the ROM and referred to by bank/addr in exchanged packet data.

    // WRAM locations for source addresses of animated sprite tile data:
    // bank:[addr] where bank is direct and [addr] is indirect

    // bank $7E (WRAM) is used to store decompressed 3bpp->4bpp tile data

    // $7E:[$0AC0] 0 -> $4050 (0x40 bytes) (top of sword slash)
    // $7E:[$0AC2] 2 -> $4150 (0x40 bytes) (bottom of sword slash)
    // $7E:[$0AC4] 4 -> $4070 (0x40 bytes) (top of shield)
    // $7E:[$0AC6] 6 -> $4170 (0x40 bytes) (bottom of shield)
    // $7E:[$0AC8] 8 -> $4090 (0x40 bytes) (top of bugnet or Zz sprites)
    // $7E:[$0ACA] A -> $4190 (0x40 bytes) (bottom of bugnet or music note sprites)

    // $10:[$0ACC] 0 -> $4000 (0x40 bytes) (top of head)
    // $10:[$0ACE] 2 -> $4100 (0x40 bytes) (bottom of head)
    // $10:[$0AD0] 4 -> $4020 (0x40 bytes) (top of body)
    // $10:[$0AD2] 6 -> $4120 (0x40 bytes) (bottom of body)
    // $10:[$0AD4] 8 -> $4040 (0x20 bytes) (top sweat/arm/hand)
    // $10:[$0AD6] A -> $4140 (0x20 bytes) (bottom sweat/arm/hand)
    // $7E:[$0AD8] C -> $40C0 (0x40 bytes) (top of movable block)
    // $7E:[$0ADA] E -> $41C0 (0x40 bytes) (bottom of movable block)

    // $7E:[$0AE0] -> $40B0 (0x20 bytes) (top of rupee)
    // $7E:[$0AE2] -> $41B0 (0x20 bytes) (bottom of rupee)

    // only if bird is active
    // $7E:[$0AF6] -> $40E0 (0x40 bytes) (top of hammer sprites)
    // $7E:[$0AF8] -> $41E0 (0x40 bytes) (bottom of hammer sprites)

    lda $4360 ; pha // preserve DMA parameters
    lda $4362 ; pha // preserve DMA parameters
    lda $4364 ; pha // preserve DMA parameters
    lda $4366 ; pha // preserve DMA parameters

    lda $4370 ; pha // preserve DMA parameters
    lda $4372 ; pha // preserve DMA parameters
    lda $4374 ; pha // preserve DMA parameters
    lda $4376 ; pha // preserve DMA parameters

    sep #$20    // m,a to  8-bit
    rep #$10    // x,y to 16-bit

    // read first 0x40 sprites from VRAM into WRAM:
    if 1 {
    lda.b   #$80 ; sta $2115    // VRAM address increment mode

    ldy.w #$1801 ; sty $4360    // DMA from WRAM to VRAM ($2118)
                   sty $4370

    //////////////////////////////////////////////////
    lda.b   #$7E ; sta $4364    // source bank
                   sta $4374
    ldy.w #$4640 ; sty $2116    // VRAM target address of chr $64, blob sprite (top left)

    rep #$20
    lda.l long(remote, pkt.dma7E_table + 0)             // top of sword
    sta $4362                   // source address (6)
    lda.l long(remote, pkt.dma7E_table + 4)             // top of shield
    sta $4372                   // source address (7)
    sep #$20

    ldx.w #$0040 ; stx $4365    // transfer size (6)
                   stx $4375    // transfer size (7)

    lda.b   #$C0 ; sta $420B    // activates DMA transfers on channel 6 and 7

    //////////////////////////////////////////////////
    ldy.w #$4740 ; sty $2116    // VRAM target address of chr $74, blob sprite (bottom left)

    rep #$20
    lda.l long(remote, pkt.dma7E_table + 2)             // bottom of sword
    sta $4362                   // source address (6)
    lda.l long(remote, pkt.dma7E_table + 6)             // bottom of shield
    sta $4372                   // source address (7)
    sep #$20

    // X = #$0040
                   stx $4365    // transfer size (6)
                   stx $4375    // transfer size (7)

    lda.b   #$C0 ; sta $420B    // activates DMA transfers on channel 6 and 7

    //////////////////////////////////////////////////
    lda.b   #$10 ; sta $4364    // source bank
                   sta $4374
    ldy.w #$4CB0 ; sty $2116    // VRAM target address of chr $CB, bubble sprite (top left)

    rep #$20
    lda.l long(remote, pkt.dma10_table + $0)             // top of head
    sta $4362                   // source address (6)
    lda.l long(remote, pkt.dma10_table + $4)             // top of body
    sta $4372                   // source address (7)
    sep #$20

    // X = #$0040
                   stx $4365    // transfer size (6)
                   stx $4375    // transfer size (7)

    lda.b   #$C0 ; sta $420B    // activates DMA transfers on channel 6 and 7

    //////////////////////////////////////////////////
    ldy.w #$4DB0 ; sty $2116    // VRAM target address of chr $DB, bubble sprite (bottom left)

    rep #$20
    lda.l long(remote, pkt.dma10_table + $2)             // bottom of head
    sta $4362                   // source address (6)
    lda.l long(remote, pkt.dma10_table + $6)             // bottom of body
    sta $4372                   // source address (7)
    sep #$20

    // X = #$0040
                   stx $4365    // transfer size (6)
                   stx $4375    // transfer size (7)

    lda.b   #$C0 ; sta $420B    // activates DMA transfers on channel 6 and 7

    //////////////////////////////////////////////////
    ldy.w #$4400 ; sty $2116    // VRAM target address of chr $40, weird unused block next to signpost (top left)

    rep #$20
    lda.l long(remote, pkt.dma10_table + $8)       // top sweat/arm/hand
    sta $4362                   // source address (6)
    sep #$20

    ldx.w #$0020 ; stx $4365    // transfer size (6)

    lda.b   #$40 ; sta $420B    // activates DMA transfers on channel 6

    //////////////////////////////////////////////////
    ldy.w #$4500 ; sty $2116    // VRAM target address of chr $50, weird unused block next to signpost (bottom left)

    rep #$20
    lda.l long(remote, pkt.dma10_table + $A)       // bottom sweat/arm/hand
    sta $4362                   // source address (6)
    sep #$20

    ldx.w #$0020 ; stx $4365    // transfer size (6)

    lda.b   #$40 ; sta $420B    // activates DMA transfers on channel 6
    }

    rep #$20    // m,a to 16-bit

    pla ; sta $4376 // restore DMA parameters
    pla ; sta $4374 // restore DMA parameters
    pla ; sta $4372 // restore DMA parameters
    pla ; sta $4370 // restore DMA parameters

    pla ; sta $4366 // restore DMA parameters
    pla ; sta $4364 // restore DMA parameters
    pla ; sta $4362 // restore DMA parameters
    pla ; sta $4360 // restore DMA parameters

nmiPostHookDone:
    sep #$30

    // This is the code our hook JML instruction replaced so we must run it here:
    lda.b $13 ; sta $2100

    // Jump back to the instruction after our JML interception:
    jml nmiPostReturn