
<p align="center">
  <img src="./img.png" width="220">
</p>

<h3 align="center">Winlator WCP Hub</h3>
<h4 align="center">Automated builds, Always up to date</h4>

---

> [!TIP]
> <details>
>  <summary><b>What exactly is Winlator-Bionic?</b></summary>
> <br>
>
> | Bionic builds | 📝 |
> |:-:|-|
> | [**Winlator-CMod**](https://github.com/coffincolors/winlator/releases) | Baseline Bionic build with excellent controller support |
> | [**Winlator-Ludashi**](https://github.com/StevenMXZ/Winlator-Ludashi/releases) | Rapidly integrates the latest upstream code while remaining close to vanilla |
> | [**Winlator-OSS**](https://github.com/Mart-01-oss/WinlatorOSS/releases) | Rapidly integrates the latest upstream code, combines CMod features with additional QOL improvements |
>
>  ---
>
> - Winlator-Bionic is a community fork based on [Pipetto-crypto](https://github.com/Pipetto-crypto)'s code. It adds modular WCP components and Box64 builds linked against Android’s Bionic libc, bringing the runtime closer to native Android while offering optional FEXCore, Arm64EC containers as an experimental path for extra performance tuning beyond the official project.
> - Meanwhile, The official Winlator and its glibc-based forks focus on a stable, general-purpose setup. Built on [brunodev85](https://github.com/brunodev85)’s Vortek graphics layer, they work reliably across many chipsets, so it’s worth trying a few combinations to see what runs best on your device. 🤞
>
>  ---
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
| FEXCore | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore-Nightly) | <!--fex--> ⛔BRRR|<a href="https://github.com/FEX-Emu/FEX/releases">🔗</a> |
| Box64-Bionic | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-BIONIC) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-BIONIC-NIGHTLY) | <!--box64--> 0.3.8 · 0.3.9| <a href="https://github.com/ptitSeb/box64/releases">🔗</a> |
| WowBox64 | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/WOWBOX64) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/WOWBOX64-NIGHTLY) | <!--box64--> 0.3.8 · 0.3.9| <a href="https://github.com/ptitSeb/box64/releases">🔗</a> |
<!--| Box64-Glibc | [**Stable**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-STABLE) &nbsp; [**Nightly**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-NIGHTLY) | Paused ||-->

<details>
<summary>💡Basic Information</summary>
<br>

| Type | 📝 |
|:-:|-|
| **FEXCore** | Focuses on accuracy and modern titles. Delivers native-like performance on high-end systems by leveraging Arm64EC architecture and hardware features like TSO |
| **Box64** | Renowned for speed and flexibility. Excellent for older titles or optimizing performance on specific hardware through extensive Dynarec customization |
| **WowBox64** | A 32-bit x86 Windows guest library that is loaded inside the Wine environment. It thunks 32-bit Windows API calls to the 64-bit host |

---

</details>

<details>
<summary>🧐 <b>UNITY SETTINGS</b></summary>
<br>

<h3>🧠 Unity scripting backends</h3>

| Backend | 🏷️ | 🔍 | 📝 |
|:-:|:-:|:-:|-|
| **Old Mono** | ❌ | Single large `UnityEngine.dll` | Technically possible, practically not worth the trouble. |
| **Modern Mono** | 🟡 | `Assembly-CSharp.dll` | Most Unity games use this. Performance can dip, but it runs. |
| **IL2CPP** | 🟢 | `GameAssembly.dll` | Performs well and safely tolerates more aggressive settings |

---

<h3>⚙️ General Modern Mono+ Settings</h3>

| Box64 | 🏷️ | ✨ | 📝 |
|:-:|:-:|:-:|-|
| **STRONGMEM** | 1+ | Essential | Uses safer memory ordering |
| **BIGBLOCK** | 2 | Recommended | Uses small JIT blocks for stability. Lower values are more stable but slower |
| **CALLRET** | 0 | Recommended | Protects the call stack from broken JIT code |
| **WEAKBARRIER** | 1+ | Optional | Reduces the performance cost of `STRONGMEM`. Disable if the game crashes |

| FEXCore | 🏷️ | ✨ | 📝 |
|:-:|:-:|:-:|-|
| **TSOEnabled** | 1 | Essential | Uses safer memory ordering. Requires hardware TSO support |
| **SMCChecks** | FULL | Recommended | Fully checks JIT code changes. Use `MTrack` only if `FULL` is too slow |
| **Multiblock** | 0 | Recommended | Disables merging multiple JIT code chunks into one big block. try `1` only if the game stays stable |

</details>

---

### ⚡ DXVK (DX9-11) & VKD3D (DX12)

| 📦 | 🏷️ | 📜 |
|-|:-:|:-:|
| [**`DXVK`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK) [**`Arm64EC`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-ARM64EC) | <!--dxvk--> 2.7.1| <a href="https://github.com/doitsujin/dxvk/releases">🔗</a> |
| [**`DXVK-gplsync`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC) [**`Arm64EC`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC-ARM64EC)| <!--gplasync--> 2.6.2-1| <a href="https://gitlab.com/Ph42oN/dxvk-gplasync/-/releases">🔗</a> |
| [**`DXVK-Sarek-async`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC) [**`Arm64EC`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC-ARM64EC) | <!--sarek--> ⛔BRRR| <a href="https://github.com/pythonlover02/DXVK-Sarek/releases">🔗</a> |
| [**`VKD3D-Proton`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON) [**`Arm64EC`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON-ARM64EC) | <!--vkd3d--> 3.0a|<a href="https://github.com/HansKristian-Work/vkd3d-proton/releases">🔗</a> |

<details>
  <summary>💡Basic Information</summary>
<br> 

| Type | 📝 |
|:-:|-|
| **Sarek**    | DXVK fork that backports QOL patches and fixes to the 1.10.x branch |
| **gplsync** | gpl cache + async shader compilation to cut visible stutter during compilation |
| **Arm64EC**  | Intended to be used with ```FEXCore``` to minimize translation and reduce overhead |

- In mobile environments, using the very latest version can actually lead to worse performance. (For now, anyway)

</details>

---
<br><br>
<p align="center">
  <img src="./img2.png" width="100">
</p>
<h3 align="center">Additional Packages and Helpful Links</h3>

---

### 🔥 Adreno Driver
| Link | 📝 |
|:-:|-|
| [**K11MCH1**](https://github.com/K11MCH1/AdrenoToolsDrivers) | Qualcomm driver for Elite (a8xx), Mesa turnip driver for a6xx - a7xx |
| [**GameNative**](https://gamenative.app/drivers/) | Qualcomm driver for Elite (a8xx), Mesa turnip driver for a6xx - a7xx |
| [**zoerakk**](https://github.com/zoerakk/qualcomm-adreno-driver) | Qualcomm driver for Elite (a8xx) |


<details>
  <summary>💡Basic Information</summary>
<br> 
  
| Type | 📝 |
|:-:|-|
| **Qualcomm driver**    | Extracted from the official Adreno driver of a recent device. Partially compatible with similar chipsets. Emulation may show reduced performance or rendering glitches |
| **Mesa turnip driver** | Open source Mesa driver with broader Vulkan support and emulator friendly behavior. Often more compatible or stable across devices |

</details>

---

### 📦 Runtime Packages

| Type | 📝 |
|-|-|
| [**Visual C++ x64**](https://aka.ms/vs/17/release/vc_redist.x64.exe) | 2015–2022 Redistributable |
| [**Visual C++ x86**](https://aka.ms/vs/17/release/vc_redist.x86.exe) | 2015–2022 Redistributable |
| [**Visual C++ ARM64**](https://aka.ms/vs/17/release/vc_redist.arm64.exe) | 2015–2022 Redistributable |
| [**Wine-Mono (*.msi)**](https://github.com/wine-mono/wine-mono/releases) | .NET runtime for Wine (**Install only when the built-in tool is not working**) |
| [**Wine-Gecko (*.msi)**](https://dl.winehq.org/wine/wine-gecko/) | HTML engine for Wine (**Install only when the built-in tool is not working**) |
| [**DirectX (June 2010)**](https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe) | **Install only if missing Legacy DirectX DLL** |
| [**PhysX Legacy**](https://www.nvidia.com/content/DriverDownload-March2009/confirmation.php?url=/Windows/9.13.0604/PhysX-9.13.0604-SystemSoftware-Legacy.msi&lang=us&type=Other) | **Install only if an old game requests PhysX DLL** |
| [**XNA Framework**](https://download.microsoft.com/download/a/c/2/ac2c903b-e6e8-42c2-9fd7-bebac362a930/xnafx40_redist.msi) | xna40. Old indie games runtime |

<details>
  <summary>💡Basic Information</summary>
<br>

- Install only the minimum necessary.
- If older VC++ is needed, try an [**AIO package**](https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/). <br>

</details>

---

### 🌐 More Repo
[**Winlator 101**](https://github.com/K11MCH1/Winlator101)

---
<br>
<h3 align="center"> Credits </h3>
<h4 align="center">
Third-party components used for packaging (such as DXVK, Wine, vkd3d-proton, FEX, etc.) retain their original upstream licenses.
WCP packages redistribute unmodified (or minimally patched) binaries, and all copyrights and credit belong to the original authors.
<br><br>

FEX [Billy Laws](https://github.com/bylaws)<br>
Box64 [ptitSeb](https://github.com/ptitSeb)<br>
DXVK [Philip Rebohle](https://github.com/doitsujin)<br>
DXVK-Sarek [pythonlover02](https://github.com/pythonlover02)<br>
DXVK-GPLAsync Patch [Ph42oN](https://gitlab.com/Ph42oN)<br>
VKD3D [Hans-Kristian Arntzen](https://github.com/HansKristian-Work)<br>

</h4>

