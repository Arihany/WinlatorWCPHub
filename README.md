<p align="center">
  <img src="./img.png" width="180">
</p>

<h3 align="center">Winlator WCP Hub</h3>

---

> [!TIP]
> <details>
>  <summary><b>What does this hub do?</b></summary><br>
>
> **Winlator WCP Hub** uses an open automated build pipeline to distribute essential `wcp` packages and provide simple, useful information about each type.
>
> Here, `wcp` refers to a custom package format used in the Winlator-Bionic fork to install components. It makes it easy to test a wide range of newer and experimental builds.
>
> Honestly, I mostly made it for my own peace of mind. 😌
>  
> ---
> 
> </details>
> <details>
>  <summary><b>What exactly is Winlator-Bionic?</b></summary><br>
>
> ### Winlator-Bionic is a community fork based on [Pipetto-crypto](https://github.com/Pipetto-crypto)’s project.
>
> It runs closer to Android’s native stack, using a more direct Vulkan path that can cut overhead and improve performance on many devices. It supports both Box64 and FEXCore/arm64ec containers and lets users mix and match components such as Wine builds and graphics layers through modular `wcp`.
> 
> --- 
>
> | Bionic builds | 📝 |
> |:-:|-|
> | [**Winlator-CMod**](https://github.com/coffincolors/winlator/releases) | Baseline Bionic build with excellent controller support. |
> | [**Winlator-Ludashi**](https://github.com/StevenMXZ/Winlator-Ludashi/releases) | Keeps up with the latest upstream code while remaining close to vanilla. Great performance. |
> | [**GameNative**](https://github.com/utkarshdalal/GameNative/releases) | Supports both glibc and bionic, featuring a sleek UI and Steam integration. |
> 
> - Somewhere deeper in this rabbit hole, even stranger forks exist, but they’re out of scope here.
>
> ---
> 
> </details>
> <br>
> 
> Add this URL in Settings to easily download all assets:
> ```
> https://raw.githubusercontent.com/Arihany/WinlatorWCPHub/refs/heads/main/pack.json
> ``` 

---

### 🌀 FEXCore & Box64

| Type | 📦 | 🏷️ | 📜 |
|:-:|:-:|:-:|:-:|
| FEXCore | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore-Nightly) | <!--fex--> |<a href="https://github.com/FEX-Emu/FEX/releases">🔗</a> |
| Box64-Bionic | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-BIONIC) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-BIONIC-NIGHTLY) | <!--box64--> | <a href="https://github.com/ptitSeb/box64/releases">🔗</a> |
| WOWBox64 | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/WOWBOX64) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/WOWBOX64-NIGHTLY) | <!--box64--> | <a href="https://github.com/ptitSeb/box64/releases">🔗</a> |
<!--| Box64-Glibc | [**Stable**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-STABLE) &nbsp; [**Nightly**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-NIGHTLY) | Paused ||-->

<details>
<summary>💡Quick Info</summary>
<br>

| Type | 📝 |
|:-:|-|
| **FEXCore** | Prioritizes accuracy. On modern setups it can give you very good compatibility without too much fuss. |
| **Box64** | Aimed at practical performance rather than perfect accuracy. Its dynarec has plenty of room for tuning, so you can adjust it per game when something starts acting weird. |
| **WowBox64** | Helps 32-bit Windows games run inside 64-bit Wine by bridging their old 32-bit calls to the 64-bit host. |

- If you see graphics/animation/physics glitches in older games, try experimenting with `BOX64_FASTNAN` `BOX64_FASTROUND` `BOX64_X87DOUBLE` `FEX_X87REDUCEDPRECISION`

---

</details>

<details>
<summary>🧐 <b>UNITY SETTINGS</b></summary>

---

### 🧠 Unity scripting backends

| Backend | 🔍 | 🫩 | 📝 |
|:-:|:-:|:-:|-|
| **Old Mono** | `UnityEngine.dll` | ❌ | Very cumbersome, and even when it runs the performance drop is severe. |
| **Mono** | `Assembly-CSharp.dll` `/MonoBleedingEdge` | 🟡 | Used by most Unity games. Performance varies, but it generally runs. |
| **IL2CPP** | `GameAssembly.dll` | 🟢 | Performs well and tolerates more aggressive settings in most cases. |

- You can identify each backend by the folders and files it is located in 🔍

---

### ⚙️ General Modern Mono Settings

| FEXCore | 🏷️ | 📝 |
|:-:|:-:|-|
| **TSO** | `1` | Keep as is. Set to `0` only for extreme performance experiments. |
| **MEMCPYSETTSO** | `0` | If you still get crashes/freezes with `TSO = 1`, set this to `1`. | 
| **VECTORTSO** | `0` | If you still get crashes/freezes with `TSO = 1` `MEMCPYSETTSO = 1`, set this to `1`. Very heavy. |
| **HALFBARRIERTSO** | `1` | Keep as is. |
| **MULTIBLOCK** | `0` | Once TSO-related settings are stable, you can try `1` for potential performance gains. |

| Box64 | 🏷️ | 📝 |
|:-:|:-:|-|
| **SAFEFLAGS** | `1` | If you still get crashes/freezes, set this to `2`. Very heavy. |
| **STRONGMEM** | `1` | If you still get crashes/freezes, set this to `2`. Very heavy. |
| **WEAKBARRIER** | `1` | Reduces the performance cost of `STRONGMEM`. Set to `0` if the game crashes. |
| **BIGBLOCK** | `0-2` | Official recommendation is `0`, but `2` often works fine in practice. |
| **FORWARD** | `128-256` | Higher values mainly increase the risk of subtle, unpredictable side effects. |
| **CALLRET** | `0` | Keep as is. |
| **WAIT** | `1` | `0` might help performance in heavily multithreaded or JIT-heavy workloads. |

- If you see graphics/animation/physics glitches in older games, try experimenting with `BOX64_FASTNAN` `BOX64_FASTROUND` `BOX64_X87DOUBLE` `FEX_X87REDUCEDPRECISION`

</details>

---

### ⚡ DXVK (DX8-11) & VKD3D (DX12)

| 📦 | 🏷️ | 📜 |
|-|:-:|:-:|
| [**`DXVK`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK) [**`arm64ec`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-ARM64EC) | <!--dxvk--> | <a href="https://github.com/doitsujin/dxvk/releases">🔗</a> |
| [**`DXVK-gplasync`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC) [**`arm64ec`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC-ARM64EC)| <!--gplasync--> | <a href="https://gitlab.com/Ph42oN/dxvk-gplasync/-/releases">🔗</a> |
| [**`DXVK-sarek-async`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC) [**`arm64ec`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC-ARM64EC) | <!--sarek--> | <a href="https://github.com/pythonlover02/DXVK-Sarek/releases">🔗</a> |
| [**`VKD3D-proton`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON) [**`arm64ec`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON-ARM64EC) | <!--vkd3d--> |<a href="https://github.com/HansKristian-Work/vkd3d-proton/releases">🔗</a> |

- DXVK `2.5.x` and later may show reduced performance when used with the `Turnip driver`.

<details>
  <summary>💡Quick Info</summary>
<br> 

| Type | 📝 |
|:-:|-|
| **sarek**    | A modernized fork of DXVK `1.10.x` with backported fixes to keep older GPUs with weaker Vulkan support more stable. If you’re still on `1.10.x`, this is a good one to try. |
| **gplasync** | `gpl` cache + `async` shader compilation to smooth out shader hitches and visible stutter. |
| **arm64ec**  | Designed to be paired with `FEXCore` to cut down translation work and keep overhead lower. |
  
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
| [**StevenMXZ**](https://github.com/StevenMXZ/freedreno_turnip-CI/releases) | Mesa Turnip driver |
| [**K11MCH1**](https://github.com/K11MCH1/AdrenoToolsDrivers/releases) | Qualcomm proprietary driver + Mesa Turnip driver |
| [**GameNative**](https://gamenative.app/drivers/) | Qualcomm proprietary driver + Mesa Turnip driver |
| [**zoerakk**](https://github.com/zoerakk/qualcomm-adreno-driver/releases) | Qualcomm proprietary driver (ELITE) |


<details>
  <summary>💡Quick Info</summary>
<br> 
  
| Type | 📝 |
|:-:|-|
| **Qualcomm driver** | Extracted from the official Adreno driver of a recent device. Partially compatible with similar chipsets. Emulation may show reduced performance or rendering glitches. |
| **Mesa turnip driver** | Open source Mesa driver with broader Vulkan support and emulator friendly behavior. Often more compatible or stable across devices. |

</details>

---

### 📦 Runtime Packages

| Type | 📝 |
|-|-|
| [**Visual C++ x64**](https://aka.ms/vs/17/release/vc_redist.x64.exe) | 2015–2022 Redistributable |
| [**Visual C++ x86**](https://aka.ms/vs/17/release/vc_redist.x86.exe) | 2015–2022 Redistributable |
| [**Visual C++ ARM64**](https://aka.ms/vs/17/release/vc_redist.arm64.exe) | 2015–2022 Redistributable |
| [**Wine-Mono**](https://dl.winehq.org/wine/wine-mono/) | .NET runtime for Wine (**Install only when the built-in tool is not working**) |
| [**Wine-Gecko**](https://dl.winehq.org/wine/wine-gecko/) | HTML engine for Wine (**Install only when the built-in tool is not working**) |
| [**DirectX (June 2010)**](https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe) | **Install only if missing Legacy DirectX DLL** |
| [**PhysX Legacy**](https://www.nvidia.com/content/DriverDownload-March2009/confirmation.php?url=/Windows/9.13.0604/PhysX-9.13.0604-SystemSoftware-Legacy.msi&lang=us&type=Other) | **Install only if an old game requests PhysX DLL** |

<details>
  <summary>💡Quick Info</summary>
<br>

- Install only the minimum necessary.
- If older VC++ is needed, try an [**AIO package**](https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/). <br>

</details>

---
<br>
<h3 align="center"> Credits </h3>
<h4 align="center">
Third-party components used for packaging (such as DXVK, Wine, vkd3d-proton, FEX, etc.) retain their original upstream licenses.
WCP packages redistribute unmodified (or minimally patched) binaries, and all copyrights and credits belong to the original authors.
<br><br>

FEX [FEX-Emu](https://github.com/FEX-Emu)<br>
Box64 [ptitSeb](https://github.com/ptitSeb)<br>
DXVK [Philip Rebohle](https://github.com/doitsujin)<br>
DXVK-Sarek [pythonlover02](https://github.com/pythonlover02)<br>
DXVK-GPLAsync Patch [Ph42oN](https://gitlab.com/Ph42oN)<br>
VKD3D [Hans-Kristian Arntzen](https://github.com/HansKristian-Work)<br>

</h4>

