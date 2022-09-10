#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <regex>

#define PLUGIN_VERSION "1.1.0"

public Plugin myinfo =
{
    name = "Stripper:Source (SP edition)",
    author = "tilgep, Stripper:Source by BAILOPAN",
    description = "Stripper:Source functionality in a Sourcemod plugin",
    version = PLUGIN_VERSION,
    url = ""
};

enum Mode
{
    Mode_None,
    Mode_Filter,
    Mode_Add,
    Mode_Modify,
}

enum SubMode
{
    SubMode_None,
    SubMode_Match,
    SubMode_Replace,
    SubMode_Delete,
    SubMode_Insert,
}

enum struct Property
{
    char key[255];
    char val[255];
    bool regex;
}

/* Stripper block struct */
enum struct Block
{
    Mode mode;
    SubMode submode;
    ArrayList match;        // Filter/Modify
    ArrayList replace;      // Modify
    ArrayList del;          // Modify
    ArrayList insert;       // Add/Modify
    bool hasClassname;      // Ensures that an add block has a classname set

    void Init()
    {
        this.mode = Mode_None;
        this.submode = SubMode_None;
        this.match = CreateArray(sizeof(Property));
        this.replace = CreateArray(sizeof(Property));
        this.del = CreateArray(sizeof(Property));
        this.insert = CreateArray(sizeof(Property));
    }

    void Clear()
    {
        this.hasClassname = false;
        this.mode = Mode_None;
        this.submode = SubMode_None;
        this.match.Clear();
        this.replace.Clear();
        this.del.Clear();
        this.insert.Clear();
    }
}

char file[PLATFORM_MAX_PATH];
Block prop; // Global current stripper block
int section;

public void OnPluginStart()
{
    prop.Init();
}

public void OnMapInit(const char[] mapName)
{
    // Parse global filters
    BuildPath(Path_SM, file, sizeof(file), "configs/stripper/global_filters.cfg");
    
    ParseFile();

    // Now parse map config
    strcopy(file, sizeof(file), mapName);
    BuildPath(Path_SM, file, sizeof(file), "configs/stripper/maps/%s.cfg", file);

    ParseFile();
}

/**
 * Parses a stripper config file
 * 
 * @param path          Path to parse from
 */
public void ParseFile()
{
    char error[128];
    int line = 0;
    int col = 0;
    section = 0;

    prop.Clear();

    SMCParser parser = SMC_CreateParser();
    SMC_SetReaders(parser, Config_NewSection, Config_KeyValue, Config_EndSection);

    SMCError result = SMC_ParseFile(parser, file, line, col);
    delete parser;

    if (result != SMCError_Okay) 
    {
        SMC_GetErrorString(result, error, sizeof(error));
        LogError("%s on line %d, col %d of %s", error, line, col, file);
    }
}

public SMCResult Config_NewSection(SMCParser smc, const char[] name, bool opt_quotes) 
{
    section++;
    if (StrEqual(name, "filter:", false) || StrEqual(name, "remove:", false))
    {
        if(prop.mode != Mode_None)
        {
            LogError("Found 'filter' block while inside another block at section %d in file '%s'", section, file);
        }

        prop.Clear();
        prop.mode = Mode_Filter;
    }
    else if (StrEqual(name, "add:", false))
    {
        if(prop.mode != Mode_None)
        {
            LogError("Found 'add' block while inside another block at section %d in file '%s'", section, file);
        }

        prop.Clear();
        prop.mode = Mode_Add;
    }
    else if (StrEqual(name, "modify:", false))
    {
        if(prop.mode != Mode_None)
        {
            LogError("Found 'modify' block while inside another block at section %d in file '%s'", section, file);
        }

        prop.Clear();
        prop.mode = Mode_Modify;
    }
    else if (prop.mode == Mode_Modify)
    {
        if (StrEqual(name, "match:", false))
        {
            prop.submode = SubMode_Match;
        }
        else if (StrEqual(name, "replace:", false))
        {
            prop.submode = SubMode_Replace;
        }
        if (StrEqual(name, "delete:", false))
        {
            prop.submode = SubMode_Delete;
        }
        if (StrEqual(name, "insert:", false))
        {
            prop.submode = SubMode_Insert;
        }
    }

    return SMCParse_Continue;
}

public SMCResult Config_KeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
    Property kv;
    strcopy(kv.key, 255, key);
    strcopy(kv.val, 255, value);
    kv.regex = FormatRegex(kv.val, strlen(value));

    switch (prop.mode)
    {
        case Mode_None:
        {
            /* 
             * we shouldn't be getting key values if we aren't in a section
             * ignore them and keep going
             */
            return SMCParse_Continue;
        }
        case Mode_Filter:
        {
            prop.match.PushArray(kv);
        }
        case Mode_Add:
        {
            // Adding an entity without a classname will crash the server
            if(StrEqual(key, "classname", false)) prop.hasClassname = true;

            prop.insert.PushArray(kv);
        }
        case Mode_Modify:
        {
            switch (prop.submode)
            {
                case SubMode_Match:
                {
                    prop.match.PushArray(kv);
                }
                case SubMode_Replace:
                {
                    prop.replace.PushArray(kv);
                }
                case SubMode_Delete:
                {
                    prop.del.PushArray(kv);
                }
                case SubMode_Insert:
                {
                    prop.insert.PushArray(kv);
                }
            }
        }
    }

    return SMCParse_Continue;
}

public SMCResult Config_EndSection(SMCParser smc)
{
    switch (prop.mode)
    {
        case Mode_Filter:
        {
            if (prop.match.Length > 0)
            {
                RunRemoveFilter();
            }

            prop.mode = Mode_None;
        }
        case Mode_Add:
        {
            if (prop.insert.Length > 0)
            {
                if(prop.hasClassname)
                {
                    RunAddFilter();
                }
                else
                {
                    LogError("Add block with no classname found at section %d in file '%s'", section, file);
                }
            }

            prop.mode = Mode_None;
        }
        case Mode_Modify:
        {
            // Exiting a modify sub-block
            if (prop.submode != SubMode_None)
            {
                prop.submode = SubMode_None;
                return SMCParse_Continue;
            }

            // Must have some match for modify blocks
            if (prop.match.Length > 0)
            {
                RunModifyFilter();
            }

            prop.mode = Mode_None;
        }
    }
    return SMCParse_Continue;
}

public void RunRemoveFilter()
{
    /* prop.match holds what we want
     * we know it has at least 1 entry here
     */

    char val2[255];

    for (int i = 0; i < EntityLump.Length(); i++)
    {
        int matches = 0;
        EntityLumpEntry entry = EntityLump.Get(i);

        for(int j = 0; j < prop.match.Length; j++)
        {
            Property kv;
            prop.match.GetArray(j, kv, sizeof(kv));

            int index = entry.GetNextKey(kv.key, val2, sizeof(val2));
            
            while (index != -1)
            {
                if (EntPropsMatch(kv.val, val2, kv.regex))
                {
                    matches++;
                    break;
                }
                
                index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
            }
        }

        if (matches == prop.match.Length)
        {
            EntityLump.Erase(i);
            i--;
        }
        delete entry;
    }
}

public void RunAddFilter()
{
    /* prop.insert holds what we want
     * we know it has at least 1 entry here
     */

    int index = EntityLump.Append();
    EntityLumpEntry entry = EntityLump.Get(index);

    for(int i = 0; i < prop.insert.Length; i++)
    {
        Property kv;
        prop.insert.GetArray(i, kv, sizeof(kv));

        entry.Append(kv.key, kv.val);
    }

    delete entry;
}

public void RunModifyFilter()
{
    /* prop.match holds at least 1 entry here
     * others may not have anything
     */

    // Nothing to do if these are all empty
    if (prop.replace.Length == 0 && prop.del.Length == 0 && prop.insert.Length == 0)
    {
        return;
    }

    char val2[255];

    for (int i = 0; i < EntityLump.Length(); i++)
    {
        int matches = 0;
        EntityLumpEntry entry = EntityLump.Get(i);

        /* Check matches */
        for(int j = 0; j < prop.match.Length; j++)
        {
            Property kv;
            prop.match.GetArray(j, kv, sizeof(kv));

            int index = entry.GetNextKey(kv.key, val2, sizeof(val2));
            
            while (index != -1)
            {
                if (EntPropsMatch(kv.val, val2, kv.regex))
                {
                    matches++;
                    break;
                }
                
                index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
            }
        }

        if (matches < prop.match.Length) 
        {
            delete entry;
            continue;
        }

        /* This entry matches, perform any changes */

        /* First do deletions */
        if (prop.del.Length > 0)
        {
            for(int j = 0; j < prop.del.Length; j++)
            {
                Property kv;
                prop.del.GetArray(j, kv, sizeof(kv));

                int index = entry.GetNextKey(kv.key, val2, sizeof(val2));
                while (index != -1)
                {
                    if (EntPropsMatch(kv.val, val2, kv.regex))
                    {
                        entry.Erase(index);
                        index--;
                    }
                    index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
                }
            }
        }

        /* do replacements */
        if (prop.replace.Length > 0)
        {
            for(int j = 0; j < prop.replace.Length; j++)
            {
                Property kv;
                prop.replace.GetArray(j, kv, sizeof(kv));

                int index = entry.GetNextKey(kv.key, val2, sizeof(val2));
                while (index != -1)
                {
                    entry.Update(index, NULL_STRING, kv.val);
                    index = entry.GetNextKey(kv.key, val2, sizeof(val2), index);
                }
            }
        }

        /* do insertions */
        if (prop.insert.Length > 0)
        {
            for(int j = 0; j < prop.insert.Length; j++)
            {
                Property kv;
                prop.insert.GetArray(j, kv, sizeof(kv));

                entry.Append(kv.key, kv.val);
            }
        }

        delete entry;
    }
}

/**
 * Checks if 2 values match
 * 
 * @param val1     First value
 * @param val2     Second value
 * @param isRegex  True if val1 should be treated as a regex pattern, false if not
 * @return         True if match, false otherwise
 *
 */
stock bool EntPropsMatch(const char[] val1, const char[] val2, bool isRegex)
{
    if (isRegex)
    {
        return SimpleRegexMatch(val2, val1) > 0;
    }
    
    return StrEqual(val1, val2);
}

stock bool FormatRegex(char[] pattern, int len)
{
    if (pattern[0] == '/' && pattern[len-1] == '/')
    {
        strcopy(pattern, len-1, pattern[1]);
        return true;
    }
    return false;
}