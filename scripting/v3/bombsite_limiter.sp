#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <multicolors>
#pragma newdecls required

public Plugin myinfo =
{
	name = "Bombsite Limiter",
	author = "Ilusion9",
	description = "Disable specified bombsites if there are fewer CTs than their accepted limit",
	version = "3.0",
	url = "https://github.com/Ilusion9/"
};

enum struct SiteInfo
{
	int entityId;
	float vecOrigin[3];
	float vecMins[3];
	float vecMaxs[3];
	char Letter;
	int limitCTs;
}

enum ChangeState
{
	Not_Changing,
	Changing_Letter,
	Changing_Limit
}

ConVar g_Cvar_GraceTime;
ConVar g_Cvar_FreezeTime;
EngineVersion g_EngineVersion;
Handle g_Timer_FreezeEnd;

SiteInfo g_BombSites[16];
ChangeState g_ChangingSettings[MAXPLAYERS + 1];

int g_NumOfBombSites;
int g_SelectedBombSite[MAXPLAYERS + 1];

public void OnPluginStart()
{
	g_EngineVersion = GetEngineVersion();
	if (g_EngineVersion != Engine_CSGO && g_EngineVersion != Engine_CSS)
	{
		SetFailState("This plugin is designed only for CS:GO and CS:S.");
	}
	
	LoadTranslations("common.phrases");
	LoadTranslations("bombsite_limiter.phrases");
	
	RegAdminCmd("sm_bombsites", Command_Bombsites, ADMFLAG_RCON);
	HookEvent("round_start", Event_RoundStart);	
	
	g_Cvar_GraceTime = FindConVar("mp_join_grace_time");
	g_Cvar_FreezeTime = FindConVar("mp_freezetime");
}

public void OnMapStart()
{
	g_NumOfBombSites = 0;
	int entity = -1;

	while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
	{
		g_BombSites[g_NumOfBombSites].entityId = entity;
		
		GetEntPropVector(entity, Prop_Send, "m_vecMins", g_BombSites[g_NumOfBombSites].vecMins); 
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", g_BombSites[g_NumOfBombSites].vecMaxs);
		
		GetMiddleOfABox(g_BombSites[g_NumOfBombSites].vecMins, g_BombSites[g_NumOfBombSites].vecMaxs, g_BombSites[g_NumOfBombSites].vecOrigin);
		
		g_BombSites[g_NumOfBombSites].Letter = 0;
		g_BombSites[g_NumOfBombSites].limitCTs = 0;

		g_NumOfBombSites++;
	}
}

public void OnConfigsExecuted()
{
	int limitCTs;
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH], buffer[256];	
	
	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_limiter/%s.cfg", map);
	KeyValues kv = new KeyValues("Bombsites");
	
	if (kv.ImportFromFile(path))
	{
		for (int i = 0; i < g_NumOfBombSites; i++)
		{
			Format(buffer, sizeof(buffer), "%0.6f %0.6f %0.6f", g_BombSites[i].vecOrigin[0], g_BombSites[i].vecOrigin[1], g_BombSites[i].vecOrigin[2]);
			if (!kv.JumpToKey(buffer))
			{
				continue;
			}
			
			kv.GetString("letter", buffer, sizeof(buffer), "");				
			g_BombSites[i].Letter = IsCharAlpha(buffer[0]) ? CharToUpper(buffer[0]) : 0;
			
			limitCTs = kv.GetNum("ct_limit", 0);
			g_BombSites[i].limitCTs = limitCTs > 0 ? limitCTs : 0;
			
			kv.GoBack();
		}
	}
	
	delete kv;
	if (g_Cvar_GraceTime)
	{
		g_Cvar_GraceTime.IntValue = 0;
	}
}

public void OnMapEnd()
{
	delete g_Timer_FreezeEnd;
	
	if (!g_NumOfBombSites)
	{
		return;
	}
	
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH], buffer[256];	
	GetCurrentMap(map, sizeof(map));
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_limiter");
	if (!DirExists(path))
	{
		CreateDirectory(path, 511);
	}
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_limiter/%s.cfg", map);
	KeyValues kv = new KeyValues("Bombsites");
	
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		if (!g_BombSites[i].Letter || !g_BombSites[i].limitCTs)
		{
			continue;
		}
		
		Format(buffer, sizeof(buffer), "%0.6f %0.6f %0.6f", g_BombSites[i].vecOrigin[0], g_BombSites[i].vecOrigin[1], g_BombSites[i].vecOrigin[2]);
		kv.JumpToKey(buffer, true);
		
		Format(buffer, sizeof(buffer), "%c", g_BombSites[i].Letter);
		kv.SetString("letter", buffer);
		
		kv.SetNum("ct_limit", g_BombSites[i].limitCTs);		
		kv.GoBack();
	}
	
	kv.Rewind();
	kv.ExportToFile(path);
	delete kv;
}

public void OnClientConnected(int client)
{
	g_ChangingSettings[client] = Not_Changing;
}

public void OnClientDisconnect_Post(int client)
{
	g_ChangingSettings[client] = Not_Changing;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	delete g_Timer_FreezeEnd;
	
	if (!g_NumOfBombSites || IsWarmupPeriod())
	{
		return;
	}
	
	float freezeTime = g_Cvar_FreezeTime ? g_Cvar_FreezeTime.FloatValue + 1.0 : 1.0;
	g_Timer_FreezeEnd = CreateTimer(freezeTime, Timer_HandleFreezeEnd);
}

public Action Timer_HandleFreezeEnd(Handle timer, any data)
{
	bool hasRestrictions = false;
	int numOfCTs = GetCounterTerroristsCount();
	
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		AcceptEntityInput(g_BombSites[i].entityId, "Enable");
		
		if (!g_BombSites[i].limitCTs || !g_BombSites[i].Letter)
		{
			continue;
		}
		
		if (numOfCTs < g_BombSites[i].limitCTs)
		{
			hasRestrictions = true;
			AcceptEntityInput(g_BombSites[i].entityId, "Disable");
			CPrintToChatAll("> %t", "Bombsite Restricted with Reason", g_BombSites[i].Letter, g_BombSites[i].limitCTs);
		}
	}
	
	if (!hasRestrictions)
	{
		CPrintToChatAll("> %t", "No Bombsites Restricted");
	}
	
	g_Timer_FreezeEnd = null;
}

public Action Command_Bombsites(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!g_NumOfBombSites)
	{
		CReplyToCommand(client, "%t", "Map Without Bombsites");
		return Plugin_Handled;
	}
	
	DisplayMenuAllBombsites(client);
	return Plugin_Handled;
}

void DisplayMenuAllBombsites(int client)
{
	char buffer[256];
	Menu menu = new Menu(Menu_AllBombsitesHandler);
	menu.SetTitle("%T", "Bombsites", client);
	
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		if (g_BombSites[i].Letter && g_BombSites[i].limitCTs)
		{
			Format(buffer, sizeof(buffer), "%T", "Bombsite Number with Settings", client, i + 1, g_BombSites[i].Letter, g_BombSites[i].limitCTs);
		}
		else
		{
			Format(buffer, sizeof(buffer), "%T", "Bombsite Number", client, i + 1);
		}
		
		menu.AddItem("", buffer);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_AllBombsitesHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		
		case MenuAction_Select:
		{
			g_SelectedBombSite[param1] = param2;
			DisplayMenuBombsiteOptions(param1);
		}
	}
}

void DisplayMenuBombsiteOptions(int client)
{
	char buffer[256];
	int selectedBombsite = g_SelectedBombSite[client];
	Menu menu = new Menu(Menu_BombsiteOptionsHandler);
	
	menu.SetTitle("%T", "Bombsite Number", client, selectedBombsite + 1);
	Format(buffer, sizeof(buffer), "%T", "Teleport to Bombsite", client);
	menu.AddItem("", buffer);
	
	if (g_BombSites[selectedBombsite].Letter)
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Change Letter", client, g_BombSites[selectedBombsite].Letter);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Set Letter", client);
	}
	menu.AddItem("", buffer);
	
	if (g_BombSites[selectedBombsite].limitCTs)
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Change Limit", client, g_BombSites[selectedBombsite].limitCTs);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Set Limit", client);
	}
	menu.AddItem("", buffer, g_BombSites[selectedBombsite].Letter ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	Format(buffer, sizeof(buffer), "%T", "Bombsite Remove Settings", client);
	menu.AddItem("", buffer, g_BombSites[selectedBombsite].limitCTs && g_BombSites[selectedBombsite].Letter ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_BombsiteOptionsHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		
		case MenuAction_Cancel:
		{
			int selectedBombsite = g_SelectedBombSite[param1];
			if (g_ChangingSettings[param1] == Changing_Letter)
			{
				CPrintToChat(param1, "%t", "Action Changing Letter Canceled", selectedBombsite + 1);
				g_ChangingSettings[param1] = Not_Changing;
			}
			
			else if (g_ChangingSettings[param1] == Changing_Limit)
			{
				CPrintToChat(param1, "%t", "Action Changing Limit Canceled", selectedBombsite + 1);
				g_ChangingSettings[param1] = Not_Changing;
			}
			
			if (param2 == MenuCancel_ExitBack)
			{
				DisplayMenuAllBombsites(param1);
			}
		}
		
		case MenuAction_Select:
		{
			int selectedBombsite = g_SelectedBombSite[param1];
			switch (param2)
			{
				case 0:
				{
					TeleportEntity(param1, g_BombSites[selectedBombsite].vecOrigin, NULL_VECTOR, NULL_VECTOR);
					CPrintToChat(param1, "%t", "Teleported to Bombsite", selectedBombsite + 1);
					DisplayMenuBombsiteOptions(param1);
				}
				
				case 1:
				{
					if (g_ChangingSettings[param1] == Changing_Limit)
					{
						CPrintToChat(param1, "%t", "Action Changing Limit Canceled", selectedBombsite + 1);
					}
					
					g_ChangingSettings[param1] = Changing_Letter;
					CPrintToChat(param1, "%t", "Type Bombsite Letter", selectedBombsite + 1);
					CPrintToChat(param1, "%t", "Abort Action");
					DisplayMenuBombsiteOptions(param1);
				}
				
				case 2:
				{
					if (g_ChangingSettings[param1] == Changing_Letter)
					{
						CPrintToChat(param1, "%t", "Action Changing Letter Canceled", selectedBombsite + 1);
					}
					
					g_ChangingSettings[param1] = Changing_Limit;
					CPrintToChat(param1, "%t", "Type Bombsite Limit", selectedBombsite + 1);
					CPrintToChat(param1, "%t", "Abort Action");
					DisplayMenuBombsiteOptions(param1);
				}
				
				case 3:
				{
					if (g_ChangingSettings[param1] == Changing_Letter)
					{
						CPrintToChat(param1, "%t", "Action Changing Letter Canceled", selectedBombsite + 1);
						g_ChangingSettings[param1] = Not_Changing;
					}
					
					else if (g_ChangingSettings[param1] == Changing_Limit)
					{
						CPrintToChat(param1, "%t", "Action Changing Limit Canceled", selectedBombsite + 1);
						g_ChangingSettings[param1] = Not_Changing;
					}

					g_BombSites[selectedBombsite].Letter = 0;
					g_BombSites[selectedBombsite].limitCTs = 0;
					
					CPrintToChat(param1, "%t", "Bombsite Settings Removed", selectedBombsite + 1);
					DisplayMenuBombsiteOptions(param1);
				}
			}
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (g_ChangingSettings[client] == Not_Changing)
	{
		return Plugin_Continue;
	}
	
	int selectedBombsite = g_SelectedBombSite[client];
	if (StrEqual(sArgs, "cancel", false))
	{
		g_ChangingSettings[client] = Not_Changing;
		CPrintToChat(client, "%t", "Bombsite Action Canceled", selectedBombsite + 1);
		return Plugin_Handled;
	}
	
	if (g_ChangingSettings[client] == Changing_Letter)
	{
		char letter = CharToUpper(sArgs[0]);
		if (!IsCharAlpha(letter))
		{
			CPrintToChat(client, "%t", "Bombsite Invalid Letter");
			CPrintToChat(client, "%t", "Abort Action");
			return Plugin_Handled;
		}
		
		g_BombSites[selectedBombsite].Letter = letter;
		CPrintToChat(client, "%t", "Bombsite Letter Changed", selectedBombsite + 1);
	}
	else if (g_ChangingSettings[client] == Changing_Limit)
	{
		int limit;
		if (!StringToIntEx(sArgs[0], limit) || limit < 1)
		{
			CPrintToChat(client, "%t", "Bombsite Invalid Limit");
			CPrintToChat(client, "%t", "Abort Action");
			return Plugin_Handled;
		}
		
		g_BombSites[selectedBombsite].limitCTs = limit;
		CPrintToChat(client, "%t", "Bombsite Limit Changed", selectedBombsite + 1);
	}
	
	g_ChangingSettings[client] = Not_Changing;
	DisplayMenuBombsiteOptions(client);
	return Plugin_Handled;
}

bool IsWarmupPeriod()
{
	if (g_EngineVersion != Engine_CSGO)
	{
		return false;
	}
	
	return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

int GetCounterTerroristsCount()
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

/* From https://github.com/Franc1sco/DevZones plugin */
void GetMiddleOfABox(const float vec1[3], const float vec2[3], float result[3])
{
	float buffer[3];
	MakeVectorFromPoints(vec1, vec2, buffer);
	for (int i = 0; i < 3; i++)
	{
		buffer[i] /= 2.0;
	}
	
	AddVectors(vec1, buffer, result);
}
