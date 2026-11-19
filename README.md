# Comnet Two-PC Lab

Comnet Two-PC Lab is a Windows desktop helper for setting up an isolated Active Directory practice network. It guides one Windows Server and one Windows client from a direct Ethernet connection to a working domain and authenticated file sharing.

![Comnet Two-PC Lab on a Windows client](docs/gui.png)

## What it sets up

- A domain controller with AD DS and DNS on the server, then a domain join on the client.
- A folder shared by each PC over SMB, with access for a dedicated domain group.
- Optional discovery in File Explorer and safe USB ejection when Windows supports it.
- Automatic restarts where required, with a temporary scheduled task that resumes setup after an administrator signs in.

## Before you start

- Use two test PCs on an isolated switch or a direct Ethernet link. Disconnect other network connections. The helper replaces the IPv4 settings on the chosen adapter.
- Use Windows Server with Desktop Experience and a client edition of Windows Pro, Enterprise, or Education. Both PCs need Windows PowerShell 5.1, working Ethernet drivers, and administrator access.
- Open **Setup-GUI.bat** to check compatibility automatically. It shows the detected edition and enables the matching setup button. On Windows Server 2012 R2 with an earlier PowerShell version, it explains that Windows Management Framework 5.1 is required before setup can start.
- Name the PCs before creating or joining the domain. `SERVER01` and `CLIENT01` work well.
- Save open work. Domain setup may restart Windows automatically.

| Setting | Server | Client |
| --- | --- | --- |
| IPv4 | 192.168.1.1 | 192.168.1.2 |
| Subnet mask | 255.255.255.0 | 255.255.255.0 |
| DNS | 192.168.1.1 | 192.168.1.1 |
| Default gateway | Blank | Blank |

## Quick start

1. Download the repository from **Code → Download ZIP** and extract it to a USB or local folder. Keep `Setup-GUI.bat` beside `_assets`.
2. Open **Setup-GUI.bat** on the server. Choose the DNS domain, short name, connected Ethernet adapter, share name, and an NTFS drive. For example, use `ieti.local`, `IETI`, and `PCShare`. Click **Set up server**.
3. Follow the password and sign-in prompts. After a restart, sign in with the account shown in the setup window. Wait for **SERVER READY** and leave the server running.
4. Open the helper on the client with the same domain and short name. Click **Set up client**, then use the server’s domain Administrator credentials to join. Sign in as a domain administrator after restart and wait for **CLIENT READY**.
5. Test access from both machines. In File Explorer, open `\\192.168.1.1\PCShare` on the client and `\\192.168.1.2\PCShare` on the server. Replace `PCShare` if you chose another share name. If prompted, use the domain’s `shareuser` account.

Create a disposable file in each remote share and check that it appears on the other PC. The shares are separate folders.

## Troubleshooting

| If you see | Try |
| --- | --- |
| No Ethernet adapter | Check the cable and link lights, then click **Refresh**. |
| Domain cannot be found | Confirm the server reached **SERVER READY** and both PCs use the same domain name. |
| PC absent from Explorer Network | Open its direct address. Explorer discovery depends on Windows and the network. |
| A leftover share folder | Use **Reuse an empty leftover share folder** for an empty folder. Choose a different share name if it contains data. |
| Resume appears stuck | Sign in as the Administrator indicated by setup. If it fails, save the on-screen message and the recovery path. |

If your PC blocks an unsigned PowerShell script, follow your organization’s policy for reviewed scripts.

## How it works

`Setup-GUI.bat` opens the WPF interface in `_assets/Setup-GUI.ps1`. The GUI saves the selected settings locally and launches `_assets/Run-Setup.ps1` with administrator approval. Passwords are entered interactively and stay out of the saved settings. The worker uses Windows services and administrative commands for network configuration, AD DS, SMB, and Task Scheduler.

After success, the helper removes its temporary resume task and staged files and leaves a summary under `%ProgramData%`. A failed run can leave some changes in place, so read its recovery message before retrying. These fixed IP addresses are for a two-PC lab. Use separate deployment planning and addressing for more machines.

## Credits

Created and maintained by [@10yukine](https://github.com/10yukine).
