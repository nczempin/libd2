using System;
using System.Text;

namespace LibD2.Game;

/// <summary>
/// One headless Diablo II game a host plays like a client: a proxy for a live server. Time moves
/// only in <see cref="Step"/>, in frames of 1/25 s of game time, as fast as the host calls it.
/// Positions are world subtiles, the same coordinates a live game reports.
/// </summary>
public sealed class Session : IDisposable
{
    private IntPtr _handle;

    /// <summary>A game on <paramref name="options"/> with the player from a .d2s (null: a fresh
    /// level 1 sorceress).</summary>
    public Session(GameOptions options, byte[]? d2s = null)
    {
        _handle = Native.d2game_create(ref options, d2s, (UIntPtr)(d2s?.Length ?? 0));
        if (_handle == IntPtr.Zero) throw new InvalidOperationException("d2game_create failed: " + System.Runtime.InteropServices.Marshal.PtrToStringAnsi(Native.d2game_last_error()));
    }

    private IntPtr H => _handle != IntPtr.Zero ? _handle : throw new ObjectDisposedException(nameof(Session));

    /// <summary>Advance <paramref name="frames"/> frames; returns the frames run.</summary>
    public int Step(int frames = 1) => Native.d2game_step(H, frames);

    /// <summary>Frames played so far.</summary>
    public ulong Frame => Native.d2game_frame(H);

    public void Walk(int x, int y, bool run) => Native.d2game_walk(H, x, y, run ? 1 : 0);
    public void Stop() => Native.d2game_stop(H);
    public void SelectSkill(bool right, int skillId) => Native.d2game_select_skill(H, right ? 1 : 0, skillId);
    public void CastAt(bool right, int x, int y) => Native.d2game_cast_at(H, right ? 1 : 0, x, y);
    public void CastOn(bool right, uint unitId) => Native.d2game_cast_on(H, right ? 1 : 0, unitId);

    /// <summary>Drink from belt cell <paramref name="cell"/> (0..3 is the row the 1..4 keys use).</summary>
    public bool UseBelt(int cell) => Native.d2game_use_belt(H, cell) == 1;

    public void Interact(uint unitId) => Native.d2game_interact(H, unitId);

    /// <summary>Send a raw C->S packet; returns the bytes the game consumed.</summary>
    public int Send(byte[] packet) => Native.d2game_send(H, packet, (UIntPtr)packet.Length);

    public PlayerState Player
    {
        get
        {
            Native.d2game_player(H, out var p);
            return p;
        }
    }

    /// <summary>The monsters of the player's level, alive and dead.</summary>
    public MonsterState[] Monsters()
    {
        var n = Native.d2game_monsters(H, null, 0);
        var arr = new MonsterState[Math.Max(0, n)];
        if (n > 0) Native.d2game_monsters(H, arr, n);
        return arr;
    }

    public MissileState[] Missiles()
    {
        var n = Native.d2game_missiles(H, null, 0);
        var arr = new MissileState[Math.Max(0, n)];
        if (n > 0) Native.d2game_missiles(H, arr, n);
        return arr;
    }

    /// <summary>The objects and warps of the player's level.</summary>
    public ObjectState[] Objects()
    {
        var n = Native.d2game_objects(H, null, 0);
        var arr = new ObjectState[Math.Max(0, n)];
        if (n > 0) Native.d2game_objects(H, arr, n);
        return arr;
    }

    /// <summary>The belt's 16 cells as Misc.txt codes ("" for an empty cell).</summary>
    public string[] Belt()
    {
        var raw = new byte[64];
        Native.d2game_belt(H, raw);
        var cells = new string[16];
        for (var i = 0; i < 16; i++) cells[i] = Encoding.ASCII.GetString(raw, i * 4, 4).TrimEnd('\0', ' ');
        return cells;
    }

    public int SkillLevel(int skillId) => Native.d2game_skill_level(H, skillId);

    /// <summary>The items of a .d2s (1.14d or D2R).</summary>
    public static SaveItem[] SaveItems(byte[] d2s)
    {
        var n = Native.d2game_save_items(d2s, (UIntPtr)d2s.Length, null, 0);
        if (n < 0) throw new InvalidOperationException("unreadable save");
        var arr = new SaveItem[n];
        if (n > 0) Native.d2game_save_items(d2s, (UIntPtr)d2s.Length, arr, n);
        return arr;
    }

    /// <summary>Living hostile monsters on a level (the Den of Evil's quest is done at 0).</summary>
    public int MonstersLeft(int levelId) => Native.d2game_monsters_left(H, levelId);

    public void Dispose()
    {
        if (_handle == IntPtr.Zero) return;
        Native.d2game_destroy(_handle);
        _handle = IntPtr.Zero;
    }
}
