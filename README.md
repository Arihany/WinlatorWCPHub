<p align="center">
  <img src="./img.png" width="180">
</p>

<h3 align="center">Winlator WCP Hub</h3>

---

> [!NOTE]
> 2026/06/27
> - Assets have been refreshed.
> - binsem assets have been added.
> - [**Proton 11 Beta 5**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/WINE) with several bug fixes. Updates will be irregular.
> - ARM64EC (and Fexcore) assets now use Valve-style build flags for better performance, though compatibility may be reduced.
> - `FEX Nightly` and `Box64` are no longer maintained because they are no longer part of my regular testing path.


> [!TIP]
> <details>
>  <summary><b>What does this hub do?</b></summary><br>
>
> **Winlator WCP Hub** uses an open automated build pipeline to distribute essential `wcp(tzst)` packages and provide simple, useful information about each type.
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
> | Bionic builds | 📖 |
> |:-:|-|
> | [**Winlator-CMod [OUTDATED]**](https://github.com/coffincolors/winlator/releases) | Baseline Bionic build with excellent controller support. |
> | [**Winlator-Ludashi**](https://github.com/StevenMXZ/Winlator-Ludashi/releases) | Keeps up with the latest upstream code while remaining close to vanilla. Great performance. |
> | [**GameNative**](https://github.com/utkarshdalal/GameNative/releases) | Supports both glibc and bionic, featuring a sleek UI and Steam integration. |
> 
>
> ---
> 
> </details>
> <br>
>
> ```
> https://raw.githubusercontent.com/Arihany/WinlatorWCPHub/refs/heads/main/pack.json
> ``` 

---

### 🌀 FEXCore

| Type | 📦 | 🏷️ | 📜 |
|:-:|:-:|:-:|:-:|
| FEXCore | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore) | <!--fex--> `2605`|<a href="https://github.com/FEX-Emu/FEX/releases">🔗</a> |

</details>

---

### ⚡ DXVK (DX9-11) & VKD3D (DX12)

| 📦 | 🏷️ | 📜 |
|-|:-:|:-:|
| [**`DXVK`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK) [**`arm64ec`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-ARM64EC) | <!--dxvk--> `3.0`| <a href="https://github.com/doitsujin/dxvk/releases">🔗</a> |
| [**`DXVK-gplasync`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC) [**`arm64ec`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC-ARM64EC)| <!--gplasync--> `3.0-1`| <a href="https://gitlab.com/Ph42oN/dxvk-gplasync/-/releases">🔗</a> |
| [**`DXVK-sarek`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC) [**`arm64ec`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC-ARM64EC) | <!--sarek--> `1.12.0`| <a href="https://github.com/pythonlover02/DXVK-Sarek/releases">🔗</a> |
| [**`VKD3D-proton`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON) [**`arm64ec`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON-ARM64EC) | <!--vkd3d--> `3.0.1`|<a href="https://github.com/HansKristian-Work/vkd3d-proton/releases">🔗</a> |

- DXVK `2.5` and later may show reduced performance when used with the `Turnip driver`.

<details>
  <summary>💡Quick Info</summary>
<br> 

| Type | 📖 |
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
<h3 align="center">Additional Packages</h3>

---

### 🔥 Adreno Driver
| Link | 📖 |
|:-:|-|
| [**StevenMXZ**](https://github.com/StevenMXZ/freedreno_turnip-CI/releases) | Qualcomm proprietary driver + Mesa Turnip driver for all |
| [**whitebelyash**](https://github.com/whitebelyash/AdrenoToolsDrivers/releases) | Mesa Turnip driver for A8XX |

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
DXVK-Binary Semaphore DxvkQueue fallback Patch [Lee Gao](https://github.com/leegao)<br>
VKD3D [Hans-Kristian Arntzen](https://github.com/HansKristian-Work)<br>
Freedreno Turnip driver [Mesa](https://mesa3d.org/)

</h4>

