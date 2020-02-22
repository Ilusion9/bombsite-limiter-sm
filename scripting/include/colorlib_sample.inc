#if defined _colorlib_sample_included
    #endinput
#endif
#define _colorlib_sample_included

#define MAX_MESSAGE_LENGTH 256
#define MAX_COLOR_LENGTH 16

char g_ColorTags[][] = {
	"default",
	"darkred",
	"purple",
	"green",
	"lightgreen",
	"lime",
	"red",
	"grey",
	"yellow",
	"bluegrey",
	"blue",
	"darkblue",
	"grey2",
	"orchid",
	"lightred",
	"orange"
};

int g_ColorHex[] = {
	0x01,
	0x02,
	0x03,
	0x04,
	0x05,
	0x06,
	0x07,
	0x08,
	0x09,
	0x0A,
	0x0B,
	0x0C,
	0x0D,
	0x0E,
	0x0F,
	0x10
};

stock void CPrintToChat(int client, const char[] message, any ...)
{
	SetGlobalTransTarget(client);
	
	char buffer[MAX_MESSAGE_LENGTH];
	int buffer_index = CPreFormat(buffer);
	VFormat(buffer[buffer_index], sizeof(buffer) - buffer_index, message, 3);
	CFormat(buffer[buffer_index], sizeof(buffer) - buffer_index);
	PrintToChat(client, buffer);
}

stock void CPrintToChatAll(const char[] message, any ...)
{
	char buffer[MAX_MESSAGE_LENGTH];
	int buffer_index = CPreFormat(buffer);
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			SetGlobalTransTarget(i);
			
			int buffer_size = sizeof(buffer) - buffer_index;
			VFormat(buffer[buffer_index], buffer_size, message, 2);
			CFormat(buffer[buffer_index], buffer_size);
			PrintToChat(i, buffer);
		}
	}
}

stock void CReplyToCommand(int client, const char[] message, any ...)
{
	SetGlobalTransTarget(client);
	char buffer[MAX_MESSAGE_LENGTH];
	
	if (GetCmdReplySource() == SM_REPLY_TO_CONSOLE)
	{
		VFormat(buffer, sizeof(buffer), message, 3);
		CRemoveTags(buffer, sizeof(buffer));
		PrintToConsole(client, buffer);
	}
	else
	{
		int buffer_index = CPreFormat(buffer);
		int buffer_size = sizeof(buffer) - buffer_index;
		VFormat(buffer[buffer_index], buffer_size, message, 3);
		CFormat(buffer[buffer_index], buffer_size);
		PrintToChat(client, buffer);
	}
}

stock void CShowActivity(int client, const char[] message, any ...)
{
	SetGlobalTransTarget(client);
	
	char buffer[MAX_MESSAGE_LENGTH];
	int buffer_index = CPreFormat(buffer);
	int buffer_size = sizeof(buffer) - buffer_index;
	VFormat(buffer[buffer_index], buffer_size, message, 3);
	CFormat(buffer[buffer_index], buffer_size);
	ShowActivity(client, buffer);
}

stock void CShowActivity2(int client, const char[] tag, const char[] message, any ...)
{
	SetGlobalTransTarget(client);

	char buffer[MAX_MESSAGE_LENGTH], buffer_tag[MAX_MESSAGE_LENGTH];

	int tag_index = CPreFormat(buffer_tag);
	int tag_size = sizeof(buffer_tag) - tag_index;
	strcopy(buffer_tag[tag_index], tag_size, tag);
	CFormat(buffer_tag[tag_index], tag_size);

	int buffer_index = CPreFormat(buffer);
	int buffer_size = sizeof(buffer) - buffer_index;
	VFormat(buffer[buffer_index], buffer_size, message, 4);
	CFormat(buffer[buffer_index], buffer_size);

	ShowActivity2(client, buffer_tag, buffer);
}

stock int CPreFormat(char[] message)
{
	int index = 1;
	message[0] = view_as<char>(0x01);
	
	if (GetEngineVersion() == Engine_CSGO)
	{
		message[index] = ' ';
		++index;
	}

	return index;
}

stock void CRemoveTags(char[] message, int maxlen)
{
	int buffer_index = 0;
	char buffer[MAX_MESSAGE_LENGTH];

	for (int i = 0; i < maxlen && message[i] != '\0'; i++)
	{
		if (message[i] == '{')
		{
			int j = i + 1;
			char color[MAX_COLOR_LENGTH];
			
			for (int icolor = 0; icolor < MAX_COLOR_LENGTH; icolor++)
			{
				if (message[j] == '}' || message[j] == '\0')
				{
					break;
				}

				color[icolor] = message[j];
				j++;
			}
			
			char hexColor;
			if (CTranslateColor(color, hexColor))
			{
				i = j;
			}
		}
		else
		{
			buffer[buffer_index] = message[i];
			buffer_index++;
		}
	}

	strcopy(message, maxlen, buffer);
}

stock void CFormat(char[] message, int maxlen)
{
	int buffer_index = 0;
	char buffer[MAX_MESSAGE_LENGTH];

	for (int i = 0; i < maxlen && message[i] != '\0'; i++)
	{
		if (message[i] == '{')
		{
			int j = i + 1;
			char color[MAX_COLOR_LENGTH];
			
			for (int icolor = 0; icolor < MAX_COLOR_LENGTH; icolor++)
			{
				if (message[j] == '}' || message[j] == '\0')
				{
					break;
				}

				color[icolor] = message[j];
				j++;
			}
			
			char hexColor;
			if (CTranslateColor(color, hexColor))
			{
				buffer[buffer_index] = hexColor;
				buffer_index++;
				i = j;
			}
		}
		else
		{
			buffer[buffer_index] = message[i];
			buffer_index++;
		}
	}

	strcopy(message, maxlen, buffer);
}

bool CTranslateColor(const char[] tag, char &hex)
{
	for (int i = 0; i < sizeof(g_ColorTags); i++)
	{
		if (StrEqual(tag, g_ColorTags[i], false))
		{
			hex = view_as<char>(g_ColorHex[i]);
			return true;
		}
	}
	
	return false;
}
