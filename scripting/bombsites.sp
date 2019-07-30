#pragma semicolon 1 
#pragma newdecls required 

#include <sourcemod> 
#include <sdktools> 
#include <cstrike> 

public Plugin myinfo =
{
    name = "Bombsite Locker",
    author = "Ilusion9",
    description = "Disable bombsites if there are fewer CTs than the accepted limit",
    version = "2.0",
    url = "https://github.com/Ilusion9/"
};

StringMap g_Configuration;

public void OnPluginStart() 
{
	LoadTranslations("bombsites.phrases");
	
	g_Configuration = new StringMap();
	
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
}

public void OnConfigsExecuted()
{
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	KeyValues kv = new KeyValues("BombSites"); 

	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsites.cfg");
	
	if (!kv.ImportFromFile(path)) 
	{
		SetFailState("The configuration file could not be read.");
	}
	
	if (kv.JumpToKey(map)) 
	{
		if (kv.GotoFirstSubKey(false))
		{
			do 
			{
				char key[64];
				kv.GetSectionName(key, sizeof(key));			
				g_Configuration.SetValue(key, kv.GetNum(NULL_STRING, 0));
				
			} while (kv.GotoNextKey(false));
		}
	}
	
	delete kv;
	
	if (g_Configuration.Size)
	{
		ConVar cvar = FindConVar("mp_join_grace_time"); 

		if (cvar)
		{
			cvar.IntValue = 0; 
		}
	}
}

public void OnMapEnd()
{
	g_Configuration.Clear();
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) 
{
	if (g_Configuration.Size)
	{
		int siteA = -1, siteB = -1;
		int ent = FindEntityByClassname(-1, "cs_player_manager");
		
		if (ent != -1)
		{
			float posA[3], posB[3];
			
			GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterA", posA); 
			GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterB", posB);
			
			ent = -1;
			while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
			{
				float vecMins[3], vecMaxs[3];
				
				GetEntPropVector(ent, Prop_Send,"m_vecMins", vecMins); 
				GetEntPropVector(ent, Prop_Send,"m_vecMaxs", vecMaxs);
				
				if (IsVecBetween(posA, vecMins, vecMaxs)) 
				{
					siteA = ent; 
				}
				
				else if (IsVecBetween(posB, vecMins, vecMaxs)) 
				{
					siteB = ent; 
				}
				
				AcceptEntityInput(ent, "Enable");
			}
		}
		
		int value;
		int numCT = GetCounterTerroristsCount();
		
		if (siteA != -1)
		{			
			if (g_Configuration.GetValue("A", value))
			{
				if (numCT < value)
				{
					AcceptEntityInput(siteA, "Disable");
					PrintToChatAll(" \x04[SITE]\x01 %t", "Single Bombsite Disabled", "\x04A\x01");
				}
			}
		}
		
		if (siteB != -1)
		{
			if (g_Configuration.GetValue("B", value))
			{
				if (numCT < value)
				{
					AcceptEntityInput(siteB, "Disable");
					PrintToChatAll(" \x04[SITE]\x01 %t", "Single Bombsite Disabled", "\x04B\x01");
				}
			}
		}
		
		if (g_Configuration.GetValue("C", value))
		{
			if (numCT < value)
			{
				ent = -1;
				while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
				{
					if (ent != siteA && ent != siteB)
					{
						AcceptEntityInput(ent, "Disable");
					}
				}
				
				PrintToChatAll(" \x04[SITE]\x01 %t", "Multiple Bombsites Disabled", "\x04C etc.\x01");
			}
		}
	}
}

stock bool IsVecBetween(const float vecVector[3], const float vecMin[3], const float vecMax[3]) 
{
	return ((vecMin[0] <= vecVector[0] <= vecMax[0]) && (vecMin[1] <= vecVector[1] <= vecMax[1]) && (vecMin[2] <= vecVector[2] <= vecMax[2])); 
}

stock int GetCounterTerroristsCount()
{
	int num;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_CT)
		{
			num++;
		}
	}
	
	return num;
}