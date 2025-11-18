
<p align="center">
  <img src="./img.png" alt="logoo" width="220">
</p>

<h3 align="center">Winlator WCP Hub</h3>
<h4 align="center">Automated builds, Always up to date</h4>

---

> [!TIP]
> <details>
>  <summary><b>What exactly is Winlator-Bionic?</b></summary>
> <br>
>  
> - Winlator Bionic refers to a community fork line originating from Pipetto-crypto’s [code](https://github.com/Pipetto-crypto/winlator/tree/winlator_bionic), which replaces or augments the stock setup with Ubuntu rootfs (Bionic/Focal), modular WCP components, and optional Arm64EC containers powered by FEXCore, allowing aggressive performance experiments that the upstream project does not officially support.
> 
> | Type | |
> |:-:|-|
> | [**Winlator-CMod**](https://github.com/coffincolors/winlator/releases) | Baseline Bionic build with excellent controller support. |
> | [**Winlator-Ludashi**](https://github.com/StevenMXZ/Winlator-Ludashi/releases) | Rapidly intergates the latest upstream code while remaining close to vanilla. |
> | [**Winlator-OSS**](https://github.com/Mart-01-oss/WinlatorOSS/releases) | Rapidly intergates the latest upstream code, combines CMod features with additional QOL improvements. |
>
> </details>
> 
> <details>
>  <summary><b>WCP?</b></summary>
> <br>
>
> - WCP is a custom component bundle for the Winlator ecosystem, originating from an older glibc fork. It is essentially a tar.zst archive with the .wcp extension. Even if WCP installation isn't supported, you can simply unpack it and use its contents anywhere if you know the basics.
>
> </details>

---

### 🌀 FEXCore & Box64

| Type | 📦 | 🏷️ | 📜 |
|:-:|:-:|:-:|:-:|
| FEXCore | [**Stable**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore) · [**Nightly**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore-Nightly) | <!--fex--> 2511|<a href="https://github.com/FEX-Emu/FEX/releases">🔗</a> |
| Box64-Bionic | Stable · [**Nightly**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-BIONIC-NIGHTLY)| <!--box64--> 0.3.8 · 0.3.9| <a href="https://github.com/ptitSeb/box64/releases">🔗</a> |
| Box64-Glibc | [**Stable**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-STABLE) · [**Nightly**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-NIGHTLY) | Paused ||
| WowBox64 |  |  | |

<details>
  <summary>💡Useful info</summary>
<br>
  
| Type | 📝 |
|:-:|-|
| **FEXCore** | Works especially well with newer games and can reach very high performance on an ARM64 system that uses an Arm64EC or Proton style environment. |
| **Box64** | Very flexible and particularly strong for older or finicky software when its dynarec settings are tuned for the host CPU. |
| **WowBox64** | A Box64 variant focused on running 32-bit x86 Windows applications through Wine on ARM64. |

- Starting with build ```2509```, FEX performance in Unity engine games has improved significantly. Older Unity titles still require proper configuration.
- Basic ```Box64``` settings for unity games: ```STRONGMEM=1+``` ```CALLRET=0``` ```WEAKBARRIER=0~1``` (```WEAKBARRIER``` can mitigate the performance hit from ```STRONGMEM```, but regressions or crashes have been reported depending on the build/version/game. If issues occur, set it to ```0```)

</details>

---

### ⚡ DXVK (DX8-11) & VKD3D (DX12)

| 📦 | 🏷️ | 📜 |
|-|:-:|:-:|
| [**DXVK**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK) · [**ARM64EC**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-ARM64EC) | <!--dxvk--> 2.7.1| <a href="https://github.com/doitsujin/dxvk/releases">🔗</a> |
| [**DXVK-GPLAsync**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC) · [**ARM64EC**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC-ARM64EC)| <!--gplasync--> 2.7.1-1| <a href="https://gitlab.com/Ph42oN/dxvk-gplasync/-/releases">🔗</a> |
| [**DXVK-Sarek**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK) · [**Async**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC) · [**ARM64EC**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC-ARM64EC) · [**Mali fix**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-MALIFIX)| <!--sarek--> 1.11.0| <a href="https://github.com/pythonlover02/DXVK-Sarek/releases">🔗</a> |
|||
| [**VKD3D-Proton**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON) · [**ARM64EC**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON-ARM64EC) | <!--vkd3d--> 3.0|<a href="https://github.com/HansKristian-Work/vkd3d-proton/releases">🔗</a> |

<details>
  <summary>💡Useful info</summary>
<br> 

| Type | 📝 |
|:-:|-|
| **Sarek**    | Backports for older Vulkan. Keeps DXVK usable on Vulkan 1.1/1.2 hardware, with practical tweaks for legacy GPUs. |
| **GPLAsync** | DXVK + Async shader compilation + GPL cache to cut visible stutter during compilation. |
| **ARM64EC**  | Designed to run with ❗FEXCore❗ to minimize translation and reduce overhead. |

</details>

---

### 🍷 Wine

| 📦 | 🏷️ | 📜 |
|:-:|:-:|:-:|
| | |

---

<br><br><br>
<h3 align="center">Additional Packages and Helpful Links</h3>

---

### 🔥 Adreno Driver
| Link | 📝 |
|:-:|-|
| [**K11MCH1**](https://github.com/K11MCH1/AdrenoToolsDrivers) | Qualcomm driver for Elite, Mesa turnip driver for a6xx - a7xx |
| [**GameNative**](https://gamenative.app/drivers/) | Qualcomm driver for Elite, Mesa turnip driver for a6xx - a7xx |
| [**zoerakk**](https://github.com/zoerakk/qualcomm-adreno-driver) | Qualcomm driver for Elite |


<details>
  <summary>💡Useful info</summary>
<br> 
  
| Type | 📝 |
|:-:|-|
| **Qualcomm driver**    | Extracted from the official Adreno driver of a recent device. Partially compatible with similar chipsets. Emulation may show reduced performance or rendering glitches. |
| **Mesa turnip driver** | Open source Mesa driver with broader Vulkan support and emulator friendly behavior. Often more compatible or stable across devices. |

</details>

---

### 📦 Runtime Packages

| Type | 📝 |
|-|-|
| [**Visual C++ x64**](https://aka.ms/vs/17/release/vc_redist.x64.exe) | 2015–2022 Redistributable |
| [**Visual C++ x86**](https://aka.ms/vs/17/release/vc_redist.x86.exe) | 2015–2022 Redistributable |
| [**Visual C++ ARM64**](https://aka.ms/vs/17/release/vc_redist.arm64.exe) | 2015–2022 Redistributable |
| [**Wine-Mono**](https://github.com/wine-mono/wine-mono/releases) | .NET runtime for Wine (*.msi) |
| [**Wine-Gecko**](https://dl.winehq.org/wine/wine-gecko/) | HTML engine for Wine (*.msi) |
| [**XNA Framework**](https://download.microsoft.com/download/a/c/2/ac2c903b-e6e8-42c2-9fd7-bebac362a930/xnafx40_redist.msi) | Old indie games runtime |
| [**DirectX (June 2010)**](https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe) | Install ONLY if missing DLL (d3dx9_43.dll...) |
| [**PhysX Legacy**](https://www.nvidia.com/content/DriverDownload-March2009/confirmation.php?url=/Windows/9.13.0604/PhysX-9.13.0604-SystemSoftware-Legacy.msi&lang=us&type=Other) | Install ONLY if a old game requests PhysX DLL |

<details>
  <summary>💡Useful info</summary>
<br>

- If VC++ errors persist in an ARM64EC container, install ```Visual C++ ARM64```
- If older VC++ is needed, try an [**AIO package**](https://github.com/abbodi1406/vcredist). <br>
- May require the official [**.NET Framework**](https://dotnet.microsoft.com/ko-kr/download/dotnet-framework) instead of Mono.

</details>

---

### 🌐 More Repo
[**Winlator 101**](https://github.com/K11MCH1/Winlator101)

---
<br><br>

<h4 align="center">All credit to the original creators.</h4><p align="center">

<h3 align="center">

[brunodev85](https://github.com/brunodev85)<br>
[bylaws](https://github.com/bylaws)<br>
[doitsujin](https://github.com/doitsujin)<br>
[Hans-Kristian Arntzen](https://github.com/HansKristian-Work)<br>
[K11MCH1](https://github.com/K11MCH1)<br>
[MESA](https://mesa3d.org/)<br>
[Ph42oN](https://gitlab.com/Ph42oN)<br>
[ptitSeb](https://github.com/ptitSeb)<br>
[pythonlover02](https://github.com/pythonlover02)<br>
[zoerakk](https://github.com/zoerakk)

</h3><p align="center">

