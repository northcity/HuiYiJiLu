# Design System Inspiration of Apple
> Source: https://github.com/VoltAgent/awesome-design-md/tree/main/design-md/apple
> Applied to: 云雀记 (Huiyijilu) iOS App

## 1. Visual Theme & Atmosphere

Apple's design philosophy is reductive to its core: every pixel exists in service
of the content, and the interface retreats until it becomes invisible. This is
minimalism as reverence for the product.

**Key Characteristics:**
- SF Pro Display/Text with optical sizing — letterforms adapt automatically to size context
- Binary light/dark rhythm: `#000000` (immersive) alternating with `#f5f5f7` (informational)
- Single accent color: Apple Blue (`#0071e3`) reserved exclusively for interactive elements
- Negative letter-spacing at all text sizes — universally tight, efficient text
- Extremely tight headline line-heights (1.07–1.14) creating compressed, billboard-like impact
- Shadow used sparingly: one soft diffused shadow or nothing at all

---

## 2. Color Palette & Roles

### Primary
| Token | Hex | SwiftUI | Role |
|---|---|---|---|
| **Apple Blue** | `#0071e3` | `Color(red: 0, green: 0.443, blue: 0.890)` | Primary CTA, interactive accent — the ONLY saturated color |
| **Near Black** | `#1d1d1f` | `Color(UIColor.label)` | Primary text on light backgrounds |
| **Light Gray** | `#f5f5f7` | `Color(UIColor.secondarySystemBackground)` | Alternate section backgrounds |
| **Pure White** | `#ffffff` | `Color(UIColor.systemBackground)` | Card surfaces, primary backgrounds |

### Text Scale (on light backgrounds)
| Role | Value | SwiftUI |
|---|---|---|
| Primary text | `#1d1d1f` | `Color(.label)` |
| Secondary text | `rgba(0,0,0,0.8)` | `Color(.secondaryLabel)` |
| Tertiary / muted | `rgba(0,0,0,0.48)` | `Color(.tertiaryLabel)` |

### Dark Mode Variants
| Token | Light | Dark |
|---|---|---|
| Surface | `#ffffff` | `#000000` |
| Alt Surface | `#f5f5f7` | `#272729` |
| Accent (same) | `#0071e3` | `#0071e3` |
| Bright link (dark bg) | — | `#2997ff` |

### Shadows
- **Card Shadow**: `Color.black.opacity(0.09)` with `.shadow(radius: 15, x: 3, y: 5)`
  - Soft, diffused, wide blur — mimics natural studio lighting
- **Interactive CTA Shadow**: `accent.opacity(0.22)` with same parameters

---

## 3. Typography Rules (iOS / SwiftUI)

SF Pro is the native iOS system font. Use `.system()` — never import a custom font.
The key is optical sizing: use Display style at large sizes, Text style at body sizes.

### Hierarchy (SwiftUI)

| Role | Size | Weight | Tracking | Notes |
|---|---|---|---|---|
| Page Title | 34pt | `.bold` | `-0.5` | NavigationTitle, main screen heading |
| Section Heading | 28pt | `.bold` | `-0.3` | Feature section titles |
| Card Title | 17pt | `.bold` | `0` | Card/list row headlines |
| Body Large | 17pt | `.regular` | `-0.374` | Standard reading text |
| Body | 15pt | `.regular` | `0` | Secondary content |
| Caption | 13pt | `.regular` | `-0.224` | Metadata, timestamps |
| Micro | 11pt | `.bold` | `0` | Pills, badges, status labels |

### Principles
- **Negative tracking at larger sizes**: Headlines and body text run tight
- **Weight restraint**: Use `.bold` (700) sparingly; most UI lives at `.regular` (400) and `.semibold` (600)
- **Rounded variant**: Only for decorative/marketing contexts; use `.default` for precision UI

---

## 4. Component Stylings

### Buttons

**Primary CTA (Apple Blue)**
```swift
// Full-width CTA button
.foregroundStyle(.white)
.background(Color(red: 0, green: 0.443, blue: 0.890), in: RoundedRectangle(cornerRadius: 8))
// or Capsule for pill-style
.background(Color(red: 0, green: 0.443, blue: 0.890), in: Capsule())
.shadow(color: Color(red: 0, green: 0.443, blue: 0.890).opacity(0.22), radius: 15, x: 3, y: 5)
```

**Secondary / Ghost**
```swift
.foregroundStyle(Color(red: 0, green: 0.443, blue: 0.890))
.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
```

**Pill Badge / Tag**
```swift
.font(.system(size: 11, weight: .bold))
.padding(.horizontal, 10).padding(.vertical, 5)
.background(accentColor.opacity(0.1))
.foregroundStyle(accentColor)
.clipShape(Capsule())
```

### Cards
```swift
.background(Color(.systemBackground))
.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
.shadow(color: .black.opacity(0.07), radius: 15, x: 3, y: 5)
// Note: NO border — Apple almost never uses visible card borders
```

### Status / Processing
```swift
// Progress/status container
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(Color(red: 0, green: 0.443, blue: 0.890).opacity(0.06))
)
```

---

## 5. Layout Principles

### Spacing (8pt grid)
| Token | Value | Use |
|---|---|---|
| `xs` | 4pt | Icon gaps, micro spacing |
| `sm` | 8pt | Compact padding, badge padding |
| `md` | 16pt | Standard card padding |
| `lg` | 20pt | Horizontal screen margins |
| `xl` | 32pt | Section separation |

### Border Radius Scale
| Token | Value | Use |
|---|---|---|
| Micro | 5–8pt | Small tags, icon backgrounds |
| Standard | 12pt | Processing/status cards |
| Card | 16pt | Content cards, feature panels |
| Large | 20pt+ | ⚠️ Avoid — too soft for precision UI |
| Pill | 9999pt / Capsule | CTAs, badges, pills |

### Whitespace Philosophy
- **Breathing room**: Each major section has 16–24pt vertical padding inside; 40–60pt between sections
- **Compression within, expansion between**: Text blocks use negative tracking (tight) while surrounding space is generous
- **Content-first**: Remove decorative elements that don't serve the content

---

## 6. Depth & Elevation

| Level | Treatment | Use |
|---|---|---|
| Flat | No shadow, solid background | Standard content sections, list items |
| Subtle Lift | `black.opacity(0.07) radius:15 x:3 y:5` | Cards, floating elements |
| Interactive CTA | `accent.opacity(0.22) radius:15 x:3 y:5` | Colored buttons |
| Focus | `2px solid #0071e3` ring | Accessibility focus states |

**Shadow Philosophy**: Apple uses shadow extremely sparingly. One soft, wide, 
offset shadow (mimicking diffused studio light). Most elements have NO shadow 
at all — elevation comes from background color contrast.

---

## 7. Do's and Don'ts

### ✅ Do
- Use Apple Blue (`#0071e3`) ONLY for interactive/CTA elements
- Use SF Pro standard (`.default` design) for precision UI text
- Apply negative letter-spacing at large text sizes (`-0.5` at 34pt+)
- Use solid Apple Blue (no gradient) for primary CTA backgrounds
- Keep card shadow soft and single-layer: `x:3 y:5 radius:15`
- Use `.ultraThinMaterial` for secondary floating elements (navigation, glass effects)
- Tight headline line-heights (1.0–1.1) for large display text

### ❌ Don't
- Don't introduce additional accent colors — blue is the entire chromatic budget
- Don't use gradient fills on CTA buttons or insight cards
- Don't use heavy multi-layer shadows
- Don't use `cardRadius > 16pt` for standard content cards
- Don't use wide letter-spacing on display text
- Don't add textures, patterns, or gradients to solid backgrounds
- Don't use `.rounded` font design for body/UI text (reserve for decorative contexts)

---

## 8. Agent Prompt Guide

### Quick Color Reference (SwiftUI)
```swift
// Apple Blue (Primary CTA)
Color(red: 0.0, green: 0.443, blue: 0.890)  // #0071e3

// Near Black (Primary text on light bg)
Color(red: 0.114, green: 0.114, blue: 0.122) // #1d1d1f — or use Color(.label)

// Light Gray (Alternate section bg)
Color(red: 0.961, green: 0.961, blue: 0.969) // #f5f5f7 — or Color(.secondarySystemBackground)

// Card shadow
Color.black.opacity(0.07)

// CTA shadow
appleBlue.opacity(0.22)
```

### Example Component Snippets
```swift
// Primary CTA button (pill)
Button("开始录音") { ... }
  .font(.system(size: 16, weight: .semibold))
  .foregroundStyle(.white)
  .padding(.horizontal, 28).padding(.vertical, 14)
  .background(Color(red: 0, green: 0.443, blue: 0.890), in: Capsule())
  .shadow(color: Color(red: 0, green: 0.443, blue: 0.890).opacity(0.22), radius: 15, x: 3, y: 5)

// Content card
VStack { ... }
  .padding(18)
  .background(Color(.systemBackground))
  .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  .shadow(color: .black.opacity(0.07), radius: 15, x: 3, y: 5)

// Status pill badge
Text("已完成")
  .font(.system(size: 11, weight: .bold))
  .padding(.horizontal, 10).padding(.vertical, 5)
  .background(Color(red: 0, green: 0.443, blue: 0.890).opacity(0.1))
  .foregroundStyle(Color(red: 0, green: 0.443, blue: 0.890))
  .clipShape(Capsule())

// Insight / feature card (solid, no gradient)
VStack { ... }
  .background(
    RoundedRectangle(cornerRadius: 16, style: .continuous)
      .fill(Color(red: 0, green: 0.443, blue: 0.890))
      .shadow(color: Color(red: 0, green: 0.443, blue: 0.890).opacity(0.22), radius: 15, x: 3, y: 5)
  )
```

### Iteration Guide
1. Every interactive element gets Apple Blue — no other accent colors
2. No gradients on solid UI backgrounds or buttons
3. Card shadows: always `x:3 y:5 radius:15`, opacity never above `0.1` for neutral shadows
4. Typography: negative tracking at 28pt+ (`-0.3`), at 34pt+ (`-0.5`)
5. Card radius: 16pt for content cards, Capsule for pills
6. Spacing base: 8pt grid — padding values should be multiples of 4 or 8
