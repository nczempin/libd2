using System;
using System.Runtime.InteropServices;

namespace LibD2.Client;

/// <summary>Layout of <c>D2ClientPlayer</c> in d2client.h: the local player as the stream described
/// it. Life, mana and stamina are whole points.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct ClientPlayer
{
    public uint Guid;
    public int ClassId, LevelId, X, Y, Level;
    public int Life, MaxLife, Mana, MaxMana, Stamina, MaxStamina;
    public int Experience, Gold, StatPoints, SkillPoints, Mode;
    /// <summary>1 once the server has said the act is loaded.</summary>
    public int Loaded;
}

/// <summary>Layout of <c>D2ClientUnit</c> in d2client.h.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct ClientUnit
{
    /// <summary>0 player, 1 monster, 2 object, 5 warp.</summary>
    public int UnitType;
    public uint Guid;
    public int ClassId, X, Y;
    /// <summary>The wire's health scale: 0..128, 128 full.</summary>
    public int Life;
    public int Mode, LevelId, IsWarp;
}

/// <summary>Layout of <c>D2ClientItem</c> in d2client.h.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct ClientItem
{
    public uint Guid;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public byte[] CodeBytes;
    /// <summary>0 stored, 1 equipped, 2 belt, 3 ground, 4 cursor, 5 dropped, 6 socketed, 7 in a vendor's store.</summary>
    public int Where;
    public uint Owner;
    /// <summary>The grid cell, or the world position on the ground.</summary>
    public int X, Y;
    /// <summary>The raw page field: 0 in no grid, otherwise the page + 1.</summary>
    public int Page;
    public int BodyLoc, Quality, Quantity;
    public uint Flags;

    /// <summary>The item code (Weapons/Armor/Misc.txt).</summary>
    public string Code => System.Text.Encoding.ASCII.GetString(CodeBytes ?? new byte[0]).TrimEnd('\0', ' ');
}

/// <summary>
/// The game as a client knows it: give it every server-&gt;client packet in order and read back the
/// local player, the units on the current level and the items the stream described. Owns no
/// connection; the caller hands over whole packets.
/// </summary>
public sealed class World : IDisposable
{
    private IntPtr _handle;

    public World(string? localName = null)
    {
        _handle = Native.d2client_create();
        if (_handle == IntPtr.Zero) throw new InvalidOperationException("d2client_create failed");
        if (localName != null) Native.d2client_set_local_name(_handle, localName);
    }

    private IntPtr H => _handle != IntPtr.Zero ? _handle : throw new ObjectDisposedException(nameof(World));

    /// <summary>Apply one whole server-&gt;client packet.</summary>
    public void Apply(byte[] packet, int offset = 0, int length = -1)
    {
        if (length < 0) length = packet.Length - offset;
        if (length <= 0) return;
        if (offset == 0) { Native.d2client_apply(H, packet, length); return; }
        var copy = new byte[length];
        Array.Copy(packet, offset, copy, 0, length);
        Native.d2client_apply(H, copy, length);
    }

    /// <summary>The local player, or null before the stream has named one.</summary>
    public ClientPlayer? Player => Native.d2client_player(H, out ClientPlayer p) == 1 ? p : (ClientPlayer?)null;

    /// <summary>The units on the current level of <paramref name="unitType"/> (0 player, 1 monster,
    /// 2 object, 5 warp), or of every type when it is negative.</summary>
    public ClientUnit[] Units(int unitType = -1)
    {
        int n = Native.d2client_units(H, unitType, null, 0);
        var units = new ClientUnit[n];
        if (n > 0) n = Native.d2client_units(H, unitType, units, units.Length);
        return n == units.Length ? units : Array.Empty<ClientUnit>();
    }

    /// <summary>Every item the stream described and did not take out of the world.</summary>
    public ClientItem[] Items()
    {
        int n = Native.d2client_items(H, null, 0);
        var items = new ClientItem[n];
        if (n > 0) n = Native.d2client_items(H, items, items.Length);
        return n == items.Length ? items : Array.Empty<ClientItem>();
    }

    /// <summary>The current level (Levels.txt id).</summary>
    public int LevelId => Native.d2client_level(H, out _);

    /// <summary>The current act's map seed.</summary>
    public uint MapSeed { get { Native.d2client_level(H, out uint seed); return seed; } }

    public void Dispose()
    {
        if (_handle == IntPtr.Zero) return;
        Native.d2client_destroy(_handle);
        _handle = IntPtr.Zero;
    }

    private static class Native
    {
        private const string Lib = "d2client";

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr d2client_create();

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void d2client_destroy(IntPtr client);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void d2client_set_local_name(IntPtr client, [MarshalAs(UnmanagedType.LPStr)] string name);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void d2client_apply(IntPtr client, byte[] packet, int len);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int d2client_player(IntPtr client, out ClientPlayer player);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int d2client_units(IntPtr client, int unitType, [Out] ClientUnit[]? units, int cap);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int d2client_items(IntPtr client, [Out] ClientItem[]? items, int cap);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int d2client_level(IntPtr client, out uint mapSeed);
    }
}
