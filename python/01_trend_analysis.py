import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates


# =========================================================
# 1. Load data
# =========================================================

df = pd.read_csv("data/daily_metrics.csv")


# =========================================================
# 2. Prepare date fields
# =========================================================

df["event_date"] = pd.to_datetime(
    df["event_date"].astype(str),
    format="%Y%m%d"
)

df["day_of_week"] = df["event_date"].dt.day_name()
df["month"] = df["event_date"].dt.to_period("M")

weekday_order = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday"
]


# =========================================================
# Helper: consistent chart formatting
# =========================================================

def format_time_axis(ax):

    ax.grid(
        axis="y",
        alpha=0.18
    )

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    ax.xaxis.set_major_locator(
        mdates.WeekdayLocator(
            byweekday=mdates.MO,
            interval=2
        )
    )

    ax.xaxis.set_major_formatter(
        mdates.DateFormatter("%b %d")
    )

    plt.setp(
        ax.get_xticklabels(),
        rotation=30,
        ha="right"
    )


# =========================================================
# 3. Users trend
# =========================================================

df["users_7d_avg"] = (
    df["users"]
    .rolling(window=7)
    .mean()
)

fig, ax = plt.subplots(figsize=(10, 5))

# Daily values: visible but deliberately de-emphasized
ax.plot(
    df["event_date"],
    df["users"],
    alpha=0.20,
    linewidth=1.2,
    label="Daily Users"
)

# Moving average: main visual signal
ax.plot(
    df["event_date"],
    df["users_7d_avg"],
    linewidth=2.4,
    label="7-Day Moving Average"
)

ax.set_title(
    "Daily Users and 7-Day Moving Average",
    fontsize=15,
    pad=12
)

ax.set_xlabel("Date")
ax.set_ylabel("Users")

ax.legend(
    frameon=False,
    loc="upper right"
)

format_time_axis(ax)

ax.margins(x=0.02)

fig.tight_layout()

fig.savefig(
    "images/01_users_trend.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# =========================================================
# 4. Users by weekday
# =========================================================

weekday_users = (
    df.groupby("day_of_week")["users"]
    .mean()
    .reindex(weekday_order)
)

print("\nAverage daily users by weekday:")
print(weekday_users.round(0))


# =========================================================
# 5. Monthly users summary
# =========================================================

monthly_users = (
    df.groupby("month")["users"]
    .mean()
)

print("\nAverage daily users by month:")
print(monthly_users.round(0))


# =========================================================
# 6. Purchase conversion trend
# =========================================================

df["conversion_7d_avg"] = (
    df["conversion_rate"]
    .rolling(window=7)
    .mean()
)

fig, ax = plt.subplots(figsize=(10, 5))

ax.plot(
    df["event_date"],
    df["conversion_rate"] * 100,
    alpha=0.20,
    linewidth=1.2,
    label="Daily Conversion Rate"
)

ax.plot(
    df["event_date"],
    df["conversion_7d_avg"] * 100,
    linewidth=2.4,
    label="7-Day Moving Average"
)

ax.set_title(
    "Purchase Conversion Trend",
    fontsize=15,
    pad=12
)

ax.set_xlabel("Date")
ax.set_ylabel("Purchase Conversion Rate (%)")

ax.legend(
    frameon=False,
    loc="upper right"
)

format_time_axis(ax)

ax.margins(x=0.02)

fig.tight_layout()

fig.savefig(
    "images/02_conversion_trend.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# =========================================================
# 7. Monthly conversion summary
# =========================================================

monthly_conversion = (
    df.groupby("month")["conversion_rate"]
    .mean()
    * 100
)

print("\nAverage daily purchase conversion rate by month (%):")
print(monthly_conversion.round(2))


# =========================================================
# 8. Conversion rate by weekday
# =========================================================

weekday_conversion = (
    df.groupby("day_of_week")["conversion_rate"]
    .mean()
    .reindex(weekday_order)
    * 100
)

print("\nAverage purchase conversion rate by weekday (%):")
print(weekday_conversion.round(2))


# =========================================================
# 9. Conversion rate by month and weekday
# =========================================================

month_weekday_conversion = (
    df.groupby(
        ["month", "day_of_week"]
    )["conversion_rate"]
    .mean()
    .unstack()
    .reindex(columns=weekday_order)
    * 100
)

pd.set_option(
    "display.max_columns",
    None
)

print(
    "\nAverage purchase conversion rate "
    "by month and weekday (%):"
)

print(
    month_weekday_conversion.round(2)
)