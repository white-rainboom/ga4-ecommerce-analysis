import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates


# =========================================================
# 1. Load data
# =========================================================

daily = pd.read_csv("data/daily_funnel.csv")
weekly = pd.read_csv("data/weekly_funnel.csv")
sensitivity = pd.read_csv("data/dedup_sensitivity.csv")


# =========================================================
# 2. Prepare dates
# =========================================================

daily["event_date"] = pd.to_datetime(
    daily["event_date"].astype(str),
    format="%Y%m%d"
)

weekly["week_start"] = pd.to_datetime(weekly["week_start"])

# Earlier November contains discontinuous add_to_cart tracking,
# so funnel interpretation is restricted to the more stable window.
daily = daily[daily["event_date"] >= pd.Timestamp("2020-11-30")].copy()

ANALYSIS_SPLIT = pd.Timestamp("2020-12-14")


# =========================================================
# Helper: consistent chart formatting
# =========================================================

def clean_axis(ax):
    ax.grid(axis="y", alpha=0.18)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


# =========================================================
# 3. Daily view-to-cart trend
# =========================================================

daily["view_to_cart_7d_avg"] = (
    daily["view_to_cart_rate"]
    .rolling(window=7)
    .mean()
)

fig, ax = plt.subplots(figsize=(10, 5))

ax.plot(
    daily["event_date"],
    daily["view_to_cart_rate"] * 100,
    alpha=0.20,
    linewidth=1.2,
    label="Daily View-to-Cart Rate"
)

ax.plot(
    daily["event_date"],
    daily["view_to_cart_7d_avg"] * 100,
    linewidth=2.4,
    label="7-Day Moving Average"
)

ax.axvline(
    ANALYSIS_SPLIT,
    linestyle="--",
    linewidth=1.4,
    alpha=0.7,
    label="Analysis Split: Dec 14"
)

ax.set_title(
    "View-to-Cart Conversion Trend",
    fontsize=15,
    pad=12
)

ax.set_xlabel("Date")
ax.set_ylabel("View-to-Cart Rate (%)")

ax.xaxis.set_major_locator(
    mdates.WeekdayLocator(byweekday=mdates.MO, interval=2)
)
ax.xaxis.set_major_formatter(
    mdates.DateFormatter("%b %d")
)

plt.setp(
    ax.get_xticklabels(),
    rotation=30,
    ha="right"
)

ax.legend(
    frameon=False,
    loc="upper right"
)

ax.margins(x=0.02)
clean_axis(ax)
fig.tight_layout()

fig.savefig(
    "images/03_view_to_cart_trend.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# =========================================================
# 4. Weekly view-to-cart trend
# =========================================================

weekly_rate_pct = weekly["view_to_cart_rate"] * 100

fig, ax = plt.subplots(figsize=(9, 5))

ax.plot(
    weekly["week_start"],
    weekly_rate_pct,
    marker="o",
    markersize=5.5,
    linewidth=2.0
)

ax.axvline(
    ANALYSIS_SPLIT,
    linestyle="--",
    linewidth=1.4,
    alpha=0.7,
    label="Analysis Split: Dec 14"
)

# Label every point directly above it
for x, y in zip(weekly["week_start"], weekly_rate_pct):
    ax.annotate(
        f"{y:.1f}%",
        (x, y),
        xytext=(0, 14),
        textcoords="offset points",
        ha="center",
        va="bottom",
        fontsize=9
    )

ax.set_title(
    "Weekly View-to-Cart Conversion",
    fontsize=15,
    pad=12
)

ax.set_xlabel("Week")
ax.set_ylabel("View-to-Cart Rate (%)")

ax.xaxis.set_major_locator(
    mdates.WeekdayLocator(byweekday=mdates.MO, interval=2)
)
ax.xaxis.set_major_formatter(
    mdates.DateFormatter("%b %d")
)

plt.setp(
    ax.get_xticklabels(),
    rotation=30,
    ha="right"
)

ax.legend(
    frameon=False,
    loc="upper right"
)

ax.set_ylim(
    weekly_rate_pct.min() - 1.2,
    weekly_rate_pct.max() + 2.2
)

ax.margins(x=0.04)
clean_axis(ax)
fig.tight_layout()

fig.savefig(
    "images/04_weekly_view_to_cart.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# =========================================================
# 5. Before / After comparison
# =========================================================

weekly["period"] = weekly["week_start"].apply(
    lambda x: "Before" if x < ANALYSIS_SPLIT else "After"
)

before_after = (
    weekly.groupby("period")
    .agg(
        view_users=("view_users", "sum"),
        cart_users=("cart_users", "sum")
    )
)

before_after["view_to_cart_rate"] = (
    before_after["cart_users"]
    / before_after["view_users"]
    * 100
)

before_after = before_after.reindex(["Before", "After"])

print("\nBefore vs After:")
print(before_after.round(2))

before_rate = before_after.loc["Before", "view_to_cart_rate"]
after_rate = before_after.loc["After", "view_to_cart_rate"]
decline_pp = after_rate - before_rate


# =========================================================
# 6. Before / After chart
# =========================================================

fig, ax = plt.subplots(figsize=(7, 4.8))

# Make bars closer by manually controlling positions
x_positions = [0.00, 0.72]
bar_width = 0.3

bars = ax.bar(
    x_positions,
    before_after["view_to_cart_rate"],
    width=bar_width
)

# X labels
ax.set_xticks(x_positions)
ax.set_xticklabels([
    "Before\nNov 30–Dec 13",
    "After\nDec 14–Jan 31"
])

# Rate labels above bars
for bar, value in zip(bars, before_after["view_to_cart_rate"]):
    ax.text(
        bar.get_x() + bar.get_width() / 2,
        value + 0.55,
        f"{value:.1f}%",
        ha="center",
        va="bottom",
        fontsize=12,
        fontweight="bold"
    )

# Main effect-size annotation
mid_x = sum(x_positions) / 2

ax.text(
    mid_x,
    max(before_after["view_to_cart_rate"]) + 2.0,
    f"{decline_pp:.1f} pp",
    ha="center",
    va="bottom",
    fontsize=12,
    fontweight="bold"
)

ax.set_title(
    "View-to-Cart Conversion: Before vs After",
    fontsize=15,
    pad=18
)

ax.set_ylabel("View-to-Cart Rate (%)")

ax.set_ylim(
    0,
    max(before_after["view_to_cart_rate"]) + 6
)

ax.set_xlim(-0.30, 1.02)

clean_axis(ax)
fig.tight_layout()

fig.savefig(
    "images/05_view_to_cart_before_after.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# =========================================================
# 7. Deduplication sensitivity robustness
# =========================================================

thresholds = sensitivity[
    sensitivity["rule"].isin(["0.1s", "1s", "5s"])
].copy()

print("\nDeduplication sensitivity:")
print(thresholds)


def max_relative_range(series):
    max_value = series.max()
    min_value = series.min()
    mean_value = series.mean()
    return (max_value - min_value) / mean_value * 100


orders_variation = max_relative_range(thresholds["orders"])
revenue_variation = max_relative_range(thresholds["revenue"])
aov_variation = max_relative_range(thresholds["aov"])

print("\nRobustness across 0.1s / 1s / 5s thresholds:")
print(f"Orders max relative variation: {orders_variation:.3f}%")
print(f"Revenue max relative variation: {revenue_variation:.3f}%")
print(f"AOV max relative variation: {aov_variation:.3f}%")