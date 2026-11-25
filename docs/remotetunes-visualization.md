# RemoteTunes Visualization — Handoff Plan

## Purpose

Replace the current RemoteTunes visualization with a clean, modern, and useful dashboard built with **FL Chart**.

The goal is not to add complex charts for their own sake. The goal is to help the user understand their music library, playback activity, tag-cleanup progress, and future Cloud Library storage at a glance.

## Recommended library

Use **FL Chart**.

```bash
flutter pub add fl_chart
```

FL Chart is a free and open-source Flutter chart library. It supports line, bar, pie, scatter, and radar charts, and works on Android, iOS, Linux, macOS, web, and Windows. [web:290][web:302]

## Why FL Chart

FL Chart is the best fit for RemoteTunes because it is:

- Free and open source
- Lightweight
- Highly customizable
- Suitable for mobile dashboards
- Good for simple music-library statistics
- Good for progress visualization
- Better than building custom charts from scratch

Do not use Syncfusion unless the app later needs advanced interactions such as zooming, panning, trackballs, crosshairs, or specialized real-time charts. Syncfusion supports more than 30 chart types and interactive real-time charts, but it is likely overkill for RemoteTunes. [web:288][web:301]

Do not use `graphview` or `flutter_graph_view` unless RemoteTunes later adds a music-relationship or artist-network feature. Those packages are for graph structures, not ordinary library dashboards. [web:289][web:291]

## Visualization locations

Add visualization to these areas:

```text
Local Library
Cloud Library
Tag Cleanup
Playback History
Storage / Settings
```

## Local Library dashboard

Show a simple overview:

```text
Library Insights

Total songs: 2,000
Artists: 320
Albums: 480
Genres: 24

[ Genre distribution ]
[ Top artists ]
[ Recently added ]
[ Tag cleanup status ]
```

### Charts

| Chart | Data |
|---|---|
| Doughnut chart | Genre distribution |
| Bar chart | Top artists |
| Bar chart | Songs per album |
| Line chart | Songs added over time |
| Stat cards | Total songs, artists, albums, genres |

## Cloud Library dashboard

Show Cloud Library usage and catalog information:

```text
Cloud Library

Songs: 320
Artists: 48
Albums: 65
Genres: 12

Storage used: 7.4 GB / 10 GB
Remaining: 2.6 GB

[ Storage usage ]
[ Genre distribution ]
[ Recently uploaded ]
```

### Charts

| Chart | Data |
|---|---|
| Progress bar | R2 storage usage |
| Doughnut chart | Genre distribution |
| Bar chart | Songs uploaded per month |
| Stat cards | Songs, artists, albums, storage used |

## Tag Cleanup dashboard

For the existing Local Library auto-tagging feature, visualize cleanup progress.

```text
Tag Cleanup

Processed: 312 / 2,000
High-confidence updates: 280
Needs review: 24
No match: 8

[====================--------------] 16%
```

### Charts

| Chart | Data |
|---|---|
| Linear progress bar | Overall completion |
| Bar chart | High-confidence updates, needs review, no match |
| Doughnut chart | Tag completeness |
| Stat cards | Processed, remaining, issues |

Use a simple `LinearProgressIndicator` for the main progress bar. Use FL Chart only for the category breakdown.

## Playback history

If playback history is already stored, show:

```text
Listening Insights

Most played songs
Most played artists
Plays this week
Plays this month
Listening time
```

### Charts

| Chart | Data |
|---|---|
| Bar chart | Most-played songs |
| Bar chart | Most-played artists |
| Line chart | Plays over time |
| Doughnut chart | Plays by genre |
| Stat cards | Total plays, listening time, active days |

Do not build playback analytics unless the app already records play events. If it does not, add this later.

## Chart types to use

Use only these chart types in v1:

| Chart | Use |
|---|---|
| Bar chart | Top artists, top genres, songs per album, tag-cleanup results |
| Doughnut/pie chart | Genre distribution, source distribution |
| Line chart | Plays over time, uploads over time, songs added over time |
| Progress bar | Tag cleanup progress, R2 storage usage |
| Stat cards | Key totals and health indicators |

Do not use these in v1:

- Radar charts
- Candlestick charts
- Financial charts
- 3D charts
- Network graphs
- Force-directed graphs
- Heatmaps
- Complex multi-axis charts

## Design rules

Keep the visualization clean and readable:

- Use one accent color per category
- Show only 5–7 categories per chart
- Put exact numbers beside chart labels
- Use dark-mode-friendly colors
- Avoid 3D charts
- Avoid too many pie slices
- Avoid unnecessary chart animations
- Make charts tappable only when tapping opens a useful filtered list
- Keep charts consistent with the app’s existing theme

### Color guidance

Use a small, consistent palette:

```text
Primary: App theme primary color
Secondary: App theme secondary color
Success: Green
Warning: Orange
Error: Red
Neutral: Gray
```

For genre colors, generate stable colors from the genre name or use a fixed palette. Do not use random colors every time the screen rebuilds.

## Interaction rules

A chart should be interactive only when interaction is useful.

Example:

```text
User taps “Rock” slice in genre chart
   |
   v
Opens Rock songs list
   |
   v
Shows 1,240 Rock songs

[ Play all on Player ]
[ Add all to queue ]
```

Do not add tap behavior if it does not lead to a useful screen.

## Example: genre distribution

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class GenrePieChart extends StatelessWidget {
  const GenrePieChart({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = [
      PieChartSectionData(
        value: 420,
        title: 'Rock',
        color: Colors.blue,
      ),
      PieChartSectionData(
        value: 310,
        title: 'OPM',
        color: Colors.green,
      ),
      PieChartSectionData(
        value: 250,
        title: 'Acoustic',
        color: Colors.orange,
      ),
      PieChartSectionData(
        value: 180,
        title: 'Instrumental',
        color: Colors.purple,
      ),
    ];

    return SizedBox(
      height: 240,
      child: PieChart(
        PieChartData(
          sections: sections,
          centerSpaceRadius: 48,
          sectionsSpace: 2,
        ),
      ),
    );
  }
}
```

## Example: top artists

```dart
BarChart(
  BarChartData(
    barGroups: [
      BarChartGroupData(
        x: 0,
        barRods: [
          BarChartRodData(toY: 120, color: Colors.blue),
        ],
      ),
      BarChartGroupData(
        x: 1,
        barRods: [
          BarChartRodData(toY: 95, color: Colors.green),
        ],
      ),
      BarChartGroupData(
        x: 2,
        barRods: [
          BarChartRodData(toY: 70, color: Colors.orange),
        ],
      ),
    ],
  ),
)
```

## Implementation notes for coding agent

- Add `fl_chart` as the visualization library.
- Replace the current visualization implementation; do not patch a poor existing chart system.
- Build reusable chart widgets:
  - `GenrePieChart`
  - `TopArtistsBarChart`
  - `LibraryLineChart`
  - `TagCleanupBarChart`
  - `StorageProgressCard`
  - `StatCard`
- Use app theme colors, not hardcoded colors.
- Support dark mode.
- Limit charts to 5–7 visible categories.
- Show exact values in labels or legends.
- Make charts responsive to screen width.
- Do not add graph/network visualization.
- Do not add advanced chart types.
- Do not add playback analytics unless play-event data already exists.
- Keep the dashboard lightweight; do not load all 2,000 songs into memory for charts.
- Aggregate data in SQLite or through SQL queries before passing it to charts.

## Build phases

### Phase 1 — Replace chart foundation

- Add FL Chart
- Create reusable chart widgets
- Create stat cards
- Apply app theme and dark mode
- Remove old visualization implementation

### Phase 2 — Local Library insights

- Genre distribution
- Top artists
- Songs per album
- Recently added songs
- Library totals

### Phase 3 — Tag Cleanup visualization

- Overall progress bar
- High-confidence updates
- Needs review
- No match
- Failed jobs
- Remaining songs

### Phase 4 — Cloud Library insights

- R2 storage usage
- Cloud song count
- Genre distribution
- Recently uploaded songs

### Phase 5 — Playback insights

Add only if play-event data exists:

- Most-played songs
- Most-played artists
- Plays over time
- Listening time
- Plays by genre

## Success criteria

The visualization feature is successful when:

- The dashboard looks clean and modern.
- Charts are readable in both light and dark mode.
- The user can see library health at a glance.
- Tag Cleanup progress is easy to understand.
- Charts do not slow down the app.
- Charts work well with 2,000 local songs.
- Data is aggregated before rendering.
- Tapping a chart category opens a useful filtered list.
- The implementation uses FL Chart consistently across the app.

## Bottom line

Use **FL Chart** as the single visualization library for RemoteTunes.

Build a simple dashboard with stat cards, genre distribution, top artists, library growth, tag-cleanup progress, and later Cloud Library storage usage. Avoid complex graph libraries and advanced chart types unless a future feature truly requires them. [web:290][web:302]
