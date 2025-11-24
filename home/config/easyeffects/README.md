# EasyEffects Headphone Safety Limiter

## Overview

This directory contains an EasyEffects preset that implements a brick-wall limiter to protect your hearing by setting an absolute maximum dB level for your headphones.

## Configuration

### Current Settings

The `headphone-safety-limiter.json` preset is **calibrated for Sony WH-1000XM4 headphones**:

- **Target Absolute SPL**: **85 dB SPL** (OSHA safe for 8+ hours)
- **Threshold**: `-32.0 dB` (digital reduction to achieve 85 dB SPL)
- **Gain Boost**: `true` (peaks limited at threshold will be normalized to 0 dB)
- **Attack**: `5.0 ms` (how quickly the limiter responds)
- **Release**: `5.0 ms` (how quickly the limiter recovers)
- **Lookahead**: `5.0 ms` (advance peak detection for smoother limiting)
- **Stereo Link**: `100%` (both channels limited together)
- **Mode**: `Herm Thin` (Hermite curve, thin variant)

### SPL Calibration for Sony WH-1000XM4

Based on independent measurements (Reference Audio Analyzer):
- **Maximum Output**: 117 dB SPL at 0 dBFS (full digital volume, Bluetooth/Active mode)
- **Digital Reduction Required**: -32 dB to achieve 85 dB SPL absolute limit

### How It Works

The limiter uses the **LSP Sidechain Limiter Stereo** plugin to ensure that no audio peaks will ever exceed **85 dB SPL** from your Sony WH-1000XM4 headphones. This is a brick-wall limiter that:

1. Monitors the input signal 5ms in advance (lookahead)
2. Applies gain reduction when peaks would exceed -32 dB (= 85 dB SPL physical output)
3. Smoothly reduces volume over 5ms (attack time)
4. Smoothly restores volume over 5ms (release time)
5. Applies makeup gain so limited peaks reach 0 dB digital (gain-boost)

### Adjusting the Absolute SPL Limit

To change the maximum SPL output, edit the `threshold` value in the JSON file.

**Sony WH-1000XM4 SPL Calibration Table:**

| Target SPL | Digital Threshold | Safe Duration | Description |
|------------|------------------|---------------|-------------|
| 85 dB SPL  | `-32.0`          | 8+ hours      | **Current setting** - OSHA safe, all-day use |
| 88 dB SPL  | `-29.0`          | 4 hours       | Slightly louder, still very safe |
| 90 dB SPL  | `-27.0`          | 2 hours       | Comfortable for music, safe for extended use |
| 95 dB SPL  | `-22.0`          | 1 hour        | Louder music, moderate protection |
| 100 dB SPL | `-17.0`          | 15 minutes    | Very loud, protection against extreme spikes |
| 105 dB SPL | `-12.0`          | 5 minutes     | Approaching dangerous levels |
| 110 dB SPL | `-7.0`           | Immediate risk | Risk of hearing damage |

**Example**: To change to 90 dB SPL maximum:
```json
"threshold": -27.0
```

**Formula**: `threshold = target_SPL - 117` (where 117 dB is the WH-1000XM4 maximum output)

### Other Adjustable Parameters

**Attack/Release Time** (smoother vs. more aggressive):
```json
"attack": 5.0,    // Range: 0.25 to 20 ms
"release": 5.0    // Range: 0.25 to 20 ms
```

**Lookahead** (better peak detection, adds latency):
```json
"lookahead": 5.0  // Range: 0.1 to 20 ms
```

**Gain Boost** (normalize limited peaks to 0 dB):
```json
"gain-boost": true  // true or false
```

**Mode Options**:
- `"Herm Thin"` - Default, smooth Hermite curve
- `"Herm Wide"` - Wider frequency response
- `"Exp Thin"` - Exponential curve (more aggressive)
- `"Line Thin"` - Linear curve (most aggressive)

## Usage

### Load the Preset

```bash
easyeffects -l headphone-safety-limiter
```

### Check Active Preset

```bash
easyeffects -s output
```

### List All Presets

```bash
easyeffects -p
```

### Auto-load on Device Connection

1. Open EasyEffects GUI
2. Load the `headphone-safety-limiter` preset
3. Go to Presets menu
4. Click "Autoload" tab
5. Add your headphone device and associate it with this preset

## NixOS Integration

The preset is automatically deployed via `hosts/hm-shared/config_writes.nix`:

```nix
".config/easyeffects/output" = {
  source = "${self}/home/config/easyeffects/output";
  recursive = true;
};
```

After editing the preset, rebuild your NixOS configuration:

```bash
sudo nixos-rebuild switch
# or for home-manager only:
home-manager switch
```

## Technical Details

- **Plugin**: LSP Sidechain Limiter Stereo (`http://lsp-plug.in/plugins/lv2/sc_limiter_stereo`)
- **Type**: Brick-wall limiter with lookahead
- **Processing**: Feed-forward sidechain with internal signal
- **Latency**: ~5ms (lookahead time)

## Safety Notes

⚠️ **Important**:
- This limiter protects against volume spikes but doesn't prevent prolonged loud listening
- Even with limiting, extended listening at high volumes can damage hearing
- Use the lowest comfortable volume level
- Take regular breaks when using headphones

## Verification

To verify the limiter is working:
1. Load the preset
2. Play audio at various volumes
3. Open EasyEffects GUI and watch the limiter's gain reduction meter
4. When audio exceeds -3 dB, you should see gain reduction being applied
