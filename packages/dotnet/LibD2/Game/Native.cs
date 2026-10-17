using System;
using System.Runtime.InteropServices;

namespace LibD2.Game;

/// <summary>Layout of <c>D2GameOptions</c> in d2game.h.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct GameOptions
{
    /// <summary>The game seed (the map seed a D2R game reports).</summary>
    public uint Seed;
    /// <summary>0 normal, 1 nightmare, 2 hell.</summary>
    public int Difficulty;
    /// <summary>Levels.txt id the player starts in.</summary>
    public int LevelId;
    /// <summary>Start position in world subtiles; 0,0 is the level's entry point.</summary>
    public int X, Y;
}

/// <summary>Layout of <c>D2GamePlayer</c> in d2game.h.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct PlayerState
{
    public uint UnitId;
    public int ClassId, LevelId, X, Y;
    public int Level, Life, MaxLife, Mana, MaxMana, Stamina, MaxStamina;
    public int Experience, Gold, StatPoints, SkillPoints;
    public int LeftSkill, RightSkill;
    public int Dead, Running, Moving, Kills;
}

/// <summary>Layout of <c>D2GameMonster</c> in d2game.h.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct MonsterState
{
    public uint UnitId;
    public int ClassId, X, Y, Life, MaxLife, Alive;
    /// <summary>0 normal, 1 champion, 2 unique, 3 superunique, 4 minion.</summary>
    public int Rank;
    public int Level, Npc;
}

/// <summary>Layout of <c>D2GameMissile</c> in d2game.h.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct MissileState
{
    public uint UnitId;
    public int MissileId, X, Y;
    public uint OwnerId;
}

/// <summary>Layout of <c>D2GameObject</c> in d2game.h.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct ObjectState
{
    public uint UnitId;
    public int ClassId, X, Y;
    /// <summary>0 object, 1 warp.</summary>
    public int Kind;
    public int DestLevel;
    public int OperateFn;
}

/// <summary>Layout of <c>D2GameItem</c> in d2game.h.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct SaveItem
{
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public byte[] CodeBytes;
    /// <summary>0 stored, 1 equipped, 2 belt, 3 ground, 4 cursor, 6 socketed.</summary>
    public int Dest;
    public int BodyLoc, X, Y, Page, Quality;
    public uint Flags;
    public int StatCount, BitLength;

    /// <summary>The item code (Weapons/Armor/Misc.txt).</summary>
    public string Code => System.Text.Encoding.ASCII.GetString(CodeBytes).TrimEnd('\0', ' ');
}

/// <summary>The raw d2game entry points; <see cref="Session"/> is the public surface.</summary>
internal static class Native
{
    private const string Lib = "d2game";

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr d2game_create(ref GameOptions opt, byte[]? d2s, UIntPtr d2sLen);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void d2game_destroy(IntPtr game);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr d2game_last_error();

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_step(IntPtr game, int frames);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern ulong d2game_frame(IntPtr game);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_walk(IntPtr game, int x, int y, int run);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_stop(IntPtr game);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_select_skill(IntPtr game, int right, int skillId);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_cast_at(IntPtr game, int right, int x, int y);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_cast_on(IntPtr game, int right, uint unitId);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_use_belt(IntPtr game, int cell);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_interact(IntPtr game, uint unitId);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_send(IntPtr game, byte[] bytes, UIntPtr len);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_player(IntPtr game, out PlayerState state);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_monsters(IntPtr game, [Out] MonsterState[]? outArr, int cap);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_missiles(IntPtr game, [Out] MissileState[]? outArr, int cap);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_objects(IntPtr game, [Out] ObjectState[]? outArr, int cap);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_belt(IntPtr game, [Out] byte[] outCodes);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_skill_level(IntPtr game, int skillId);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_monsters_left(IntPtr game, int levelId);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int d2game_save_items(byte[] bytes, UIntPtr len, [Out] SaveItem[]? outArr, int cap);
}
