#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Bombsite Locker",
	author = "Ilusion9",
	description = "Disable specified bomb sites if there are fewer CTs than their accepted limit",
	version = "3.0",
	url = "https://github.com/Ilusion9/"
};

#define MAX_BOMBSITES	10
enum struct SiteInfo
{
	int EntityId;
	int HammerId;
	char Letter;
	int LimitCT;
}

ConVar g_Cvar_FreezeTime;
Handle g_Timer_FreezeEnd;

SiteInfo g_BombSites[MAX_BOMBSITES];
int g_NumOfBombSites;

bool g_IsChangingSettings[MAXPLAYERS + 1];
int g_SelectedBombSite[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("bombsitelocker.phrases");
	
	RegAdminCmd("sm_bombsites", Command_Bombsites, ADMFLAG_RCON);
	
	HookEvent("round_start", Event_RoundStart);	
	g_Cvar_FreezeTime = FindConVar("mp_freezetime");
}

public void OnMapStart()
{
	g_NumOfBombSites = 0;
	int entity = -1;
	
	while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
	{
		g_BombSites[g_NumOfBombSites].EntityId = entity;
		g_BombSites[g_NumOfBombSites].HammerId = GetEntityHammerId(entity);
		g_BombSites[g_NumOfBombSites].Letter = 0;
		g_BombSites[g_NumOfBombSites].LimitCT = 0;
		g_NumOfBombSites++;
	}
}

public void OnConfigsExecuted()
{
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];	
	GetCurrentMap(map, sizeof(map));
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker/%s.sites.cfg", map);
	KeyValues kv = new KeyValues("Bombsites");
	
	if (kv.ImportFromFile(path))
	{
		if (kv.GotoFirstSubKey(false))
		{
			do
			{
				char section[65];
				kv.GetSectionName(section, sizeof(section));
				int hammerId = StringToInt(section);
				
				for (int i = 0; i < g_NumOfBombSites; i++)
				{
					if (g_BombSites[i].HammerId == hammerId)
					{
						char letter[3];
						kv.GetString("letter", letter, sizeof(letter), "\n");
						g_BombSites[i].Letter = letter[0];
						g_BombSites[i].LimitCT = kv.GetNum("ct_limit", 0);
						break;
					}
				}
				
			} while (kv.GotoNextKey(false));
		}
	}
	
	delete kv;
	SetConVar("mp_join_grace_time", "0");
}

public void OnMapEnd()
{
	delete g_Timer_FreezeEnd;
	
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];	
	GetCurrentMap(map, sizeof(map));
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker");
	if (!DirExists(path))
	{
		CreateDirectory(path, 0777);
	}
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker/%s.sites.cfg", map);
	KeyValues kv = new KeyValues("Bombsites");
	kv.ImportFromFile(path);
	
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		char key[65];
		Format(key, sizeof(key), "%d", g_BombSites[i].HammerId);
		
		if (!g_BombSites[i].Letter || !g_BombSites[i].LimitCT)
		{
			if (kv.JumpToKey(key))
			{
				kv.DeleteThis();
				kv.GoBack();
			}
			
			continue;
		}
		
		kv.JumpToKey(key, true);
		char letter[3];
		Format(letter, sizeof(letter), "%c", g_BombSites[i].Letter);
		
		kv.SetString("letter", letter);
		kv.SetNum("ct_limit", g_BombSites[i].LimitCT);		
		kv.GoBack();
	}
	
	kv.ExportToFile(path);
	delete kv;
}

public void OnClientConnected(int client)
{
	g_IsChangingSettings[client] = false;
}

public void OnClientDisconnect_Post(int client)
{
	g_IsChangingSettings[client] = false;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	delete g_Timer_FreezeEnd;
	
	if (IsWarmupPeriod())
	{
		return;
	}
	
	g_Timer_FreezeEnd = CreateTimer(g_Cvar_FreezeTime.FloatValue + 1.0, Timer_HandleFreezeEnd);
}

public Action Timer_HandleFreezeEnd(Handle timer, any data)
{
	int numOfCTs = GetCounterTerroristsCount();
	if (numOfCTs)
	{
		for (int i = 0; i < g_NumOfBombSites; i++)
		{
			AcceptEntityInput(g_BombSites[i].EntityId, "Enable");
			
			if (!g_BombSites[i].LimitCT || !g_BombSites[i].Letter)
			{
				continue;
			}
			
			if (numOfCTs < g_BombSites[i].LimitCT)
			{
				AcceptEntityInput(g_BombSites[i].EntityId, "Disable");
				PrintToChatAll("%t", "Bombsite Disabled Reason", g_BombSites[i].Letter, g_BombSites[i].LimitCT);
			}
		}
	}
	
	g_Timer_FreezeEnd = null;
}

public Action Command_Bombsites(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] %t", "Command is in-game only");
		return Plugin_Handled;
	}
	
	if (!g_NumOfBombSites)
	{
		ReplyToCommand(client, "[SM] %t", "Map Without Bombsites");
		return Plugin_Handled;
	}
	
	ShowBombSitesMenu(client);
	return Plugin_Handled;
}

void ShowBombSitesMenu(int client)
{
	Menu menu = new Menu(Menu_BombSitesHandler);
	menu.SetTitle("%T", "Bombsites", client);
	
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		char buffer[65];
		Format(buffer, sizeof(buffer), "%T", "Bombsite Number", client, i + 1);
		menu.AddItem("", buffer);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_BombSitesHandler(Menu menu, MenuAction action, int param1, int param2)
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
			ShowOptionsMenu(param1);
		}
	}
}

void ShowOptionsMenu(int client)
{
	char buffer[65];
	int option = g_SelectedBombSite[client];
	Menu menu = new Menu(Menu_OptionsHandler);
	
	menu.SetTitle("%T", "Bombsite Number", client, option + 1);
	Format(buffer, sizeof(buffer), "%T", "Teleport To Bombsite", client);
	menu.AddItem("", buffer);
	
	if (g_BombSites[option].LimitCT && g_BombSites[option].Letter)
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Change Settings", client, g_BombSites[option].Letter, g_BombSites[option].LimitCT);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Create Settings", client);
	}
	menu.AddItem("", buffer);
	
	if (g_BombSites[option].LimitCT && g_BombSites[option].Letter)
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Remove Settings", client);
		menu.AddItem("", buffer);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_OptionsHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		
		case MenuAction_Cancel:
		{
			if (g_IsChangingSettings[param1])
			{
				PrintToChat(param1, "[SM] %t", "Bombsite Action Canceled", g_SelectedBombSite[param1] + 1);
				g_IsChangingSettings[param1] = false;
			}
			
			if (param2 == MenuCancel_ExitBack)
			{
				ShowBombSitesMenu(param1);
			}
		}
		
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:
				{
					int option = g_SelectedBombSite[param1];
					int ent = g_BombSites[option].EntityId;
					
					float origin[3], vecMins[3], vecMaxs[3];
					GetEntPropVector(ent, Prop_Send, "m_vecMins", vecMins); 
					GetEntPropVector(ent, Prop_Send, "m_vecMaxs", vecMaxs);
					
					GetMiddleOfABox(vecMins, vecMaxs, origin);
					TeleportEntity(param1, origin, NULL_VECTOR, NULL_VECTOR);
					
					PrintToChat(param1, "[SM] %t", "Teleported To Bombsite", g_SelectedBombSite[param1] + 1);
					ShowOptionsMenu(param1);
				}
				
				case 1:
				{
					g_IsChangingSettings[param1] = true;
					PrintToChat(param1, "[SM] %t", "Type Bombsite Settings");
					PrintToChat(param1, "[SM] %t", "Bombsite Abort Action");
					ShowOptionsMenu(param1);
				}
				
				case 2:
				{
					if (g_IsChangingSettings[param1])
					{
						PrintToChat(param1, "[SM] %t", "Bombsite Action Canceled", g_SelectedBombSite[param1] + 1);
						g_IsChangingSettings[param1] = false;
					}

					int option = g_SelectedBombSite[param1];
					g_BombSites[option].Letter = 0;
					g_BombSites[option].LimitCT = 0;
					
					PrintToChat(param1, "[SM] %t", "Bombsite Settings Removed");
					ShowOptionsMenu(param1);
				}
			}
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_IsChangingSettings[client])
	{
		return Plugin_Continue;
	}
	
	if (StrEqual(sArgs, "cancel", false))
	{
		g_IsChangingSettings[client] = false;
		PrintToChat(client, "[SM] %t", "Bombsite Action Canceled", g_SelectedBombSite[client] + 1);
		return Plugin_Handled;
	}
	
	char letter = sArgs[0];
	int option = g_SelectedBombSite[client];
	
	if (!IsCharAlpha(letter))
	{
		PrintToChat(client, "[SM] %t", "Bombsite Invalid Letter");
		PrintToChat(client, "[SM] %t", "Bombsite Abort Action");
		return Plugin_Handled;
	}
	
	char buffer[65];
	Format(buffer, sizeof(buffer), "%s", sArgs);
	ReplaceString(buffer, sizeof(buffer), " ", "");
	
	int limit;
	if (!StringToIntEx(sArgs[1], limit) || limit < 1)
	{
		PrintToChat(client, "[SM] %t", "Bombsite Invalid Limit");
		PrintToChat(client, "[SM] %t", "Bombsite Abort Action");
		return Plugin_Handled;
	}
	
	g_IsChangingSettings[client] = false;
	g_BombSites[option].Letter = letter;
	g_BombSites[option].LimitCT = limit;

	PrintToChat(client, "[SM] %t", "Bombsite Settings Changed", letter, limit);
	ShowOptionsMenu(client);
	return Plugin_Handled;
}

int GetEntityHammerId(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_iHammerID");
}

bool IsWarmupPeriod()
{
	return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

void SetConVar(const char[] name, const char[] value)
{
	ConVar cvar = FindConVar(name);
	if (cvar)
	{
		cvar.SetString(value);
	}
}

int GetCounterTerroristsCount()
{
	int num = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_CT)
		{
			num++;
		}
	}

	return num;
}

/* From devzones plugin */
void GetMiddleOfABox(const float vec1[3], const float vec2[3], float buffer[3])
{
	float mid[3];
	MakeVectorFromPoints(vec1, vec2, mid);
	mid[0] = mid[0] / 2.0;
	mid[1] = mid[1] / 2.0;
	mid[2] = mid[2] / 2.0;
	AddVectors(vec1, mid, buffer);
}
