<h1 align="center">🚌 Smart Line Namer</h1>
<p align="center"><strong>Clear, human-readable line names for Transport Fever 3.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/game-Transport%20Fever%203-07c1d8" alt="Transport Fever 3">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
</p>

<h2>What it does</h2>
<p>Adds two auto-rename schemes to the line manager's wand button. They turn the game's default line names into names that actually describe the line, so you can navigate long line lists at a glance.</p>

<h2>Schemes</h2>

<h3>Vehicle - Route</h3>
<p>Names the line by vehicle type and direction.</p>
<table>
  <tr><th>Line</th><th>Name</th></tr>
  <tr><td>Train between towns</td><td><code>Train: Gukovo — Chekalin</code></td></tr>
  <tr><td>Bus within a town</td><td><code>Bus Gukovo: Center — North</code></td></tr>
  <tr><td>Truck between industries</td><td><code>Truck: Quarry — Factory</code></td></tr>
</table>

<h3>Vehicle - Stops</h3>
<p>Names the line by vehicle type and the first and last station.</p>
<table>
  <tr><th>Line</th><th>Name</th></tr>
  <tr><td>Train between towns</td><td><code>Train: Central — Riverside</code></td></tr>
  <tr><td>Tram within a town</td><td><code>Tram Gukovo: Factory — Park</code></td></tr>
  <tr><td>Ship</td><td><code>Ship: Port — Oil Terminal</code></td></tr>
</table>

<h2>How it works</h2>
<p>Every name combines a <strong>vehicle type</strong> (bus, truck, tram, train, plane or ship — with passenger/cargo awareness) with a <strong>route</strong> or <strong>stops</strong> part:</p>
<ul>
  <li><strong>Route</strong> — the two towns for inter-city lines, or a direction (Center/North/South/East/West) from the town center for lines within a single town.</li>
  <li><strong>Stops</strong> — the first and last station names. A station named after its own town is shown as <em>Station</em> (<em>Вокзал</em> in Russian).</li>
</ul>

<h2>How to use</h2>
<p>Create or select a line, open the auto-rename dialog (the wand button) and choose the <strong>Vehicle - Route</strong> or <strong>Vehicle - Stops</strong> scheme.</p>

<h2>Installation</h2>
<p>Subscribe on <a href="https://mod.io/g/transportfever3">mod.io</a>, or copy the mod folder into the game's <code>staging_area</code> directory.</p>

<h2>Localization</h2>
<p>All names are localized. The mod ships with English and Russian translations.</p>

<h2>License</h2>
<p>MIT © 2026 isNightmareDream</p>
