# Home, AI usage, and app language

The Home page retains music and calendar. Calendar preferences are available again in Settings → Calendar, including the existing permission and calendar-selection controls.

AI provider selectors now show only the provider mark and name. Quota windows below them show the remaining percentage, short progress bar, reset time, and pin control. The collapsed notch continues to use the same compact rings and music geometry.

Pausing a provider hides it from the page and pin menu. If it was selected, the page selects the first remaining enabled provider. If all providers are paused, a single settings entry replaces the quota interface. Providers can be re-enabled in Settings → AI Usage.

Settings → General → Language offers Follow system, 简体中文 and English. Restart to apply the selection across native menus and windows. The selection persists; switching back to Follow system removes only the app language override. Account credentials and quota pins are preserved. Existing upstream translations are retained; additional QuotaNotch strings have English and Simplified Chinese translations.

Two replacement icon concepts were rejected during review. This change deliberately leaves the existing shipped app icon intact pending a new visual direction.
