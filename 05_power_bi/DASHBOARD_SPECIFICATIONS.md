# Power BI Dashboard Specifications

## Dashboard Architecture Overview

### Dashboard Suite (4 Main Dashboards)

---

## 1. EXECUTIVE DASHBOARD

**Purpose:** C-Level metrics and business performance overview  
**Refresh:** 5-minute intervals  
**Audience:** CEO, CFO, COO

### Page 1: Business Performance

**KPI Cards (Top Row):**

- Total Revenue (Current Month)
  - Format: Currency with sparkline
  - Drill-through: Revenue by category
- Total Orders (Current Month)
  - Format: Number with % change vs. last month
  - Drill-through: Orders by day
- Active Customers (Current Month)
  - Format: Number with trend
  - Drill-through: New vs. returning

- AOV (Average Order Value)
  - Format: Currency with % trend
  - Drill-through: AOV by segment

**Visualizations:**

1. Revenue Trend Line Chart (Last 12 Months)
   - Axes: Month, Revenue
   - Color: Gradient (low=red, high=green)
   - Tooltip: Revenue, MoM %, YoY %

2. Top 5 Categories by Revenue (Horizontal Bar)
   - Sorting: By revenue descending
   - Labels: Category name, revenue amount
   - Color: Category-specific

3. Top 10 Products by Revenue (Table)
   - Columns: Product, Category, Revenue, % of Total
   - Sorting: By revenue desc
   - Conditional formatting: Revenue (green gradient)

4. Order Status Breakdown (Pie Chart)
   - Segments: Pending, Processing, Shipped, Delivered, Cancelled
   - Labels: Count and %
   - Colors: Standard traffic light colors

5. Geographic Distribution (Map Visual)
   - Bubbles: Size = Revenue
   - Color: By number of customers
   - Drill-through: City-level detail

**Filters (Top Level):**

- Date Range Slider (1 month to 1 year)
- Category Multi-select
- Payment Method
- Order Status

---

## 2. CUSTOMER DASHBOARD

**Purpose:** Customer segmentation, retention, and acquisition  
**Refresh:** Daily  
**Audience:** VP Sales, Marketing Manager

### Page 1: RFM Segmentation

**KPI Cards:**

- Total Customers
- Champions Count (with trend)
- At-Risk Count (with highlight)
- Churn Rate %

**Visualizations:**

1. RFM Segment Distribution (Donut Chart)
   - Segments: Champions, Loyal, Potential, New, At-Risk, Lost
   - Size: Number of customers
   - Highlight: At-Risk & Lost in red

2. Segment Revenue Contribution (Stacked Bar)
   - X-axis: Segments
   - Y-axis: Revenue (stacked by segment)
   - Hover: Show customer count

3. Cohort Retention Matrix (Heatmap)
   - Rows: Cohort month
   - Columns: Months since first purchase
   - Color: Retention %
   - Values: Customer count

4. Customer Lifetime Value Distribution (Histogram)
   - X-axis: CLV ranges ($0-500, $500-1000, etc.)
   - Y-axis: Customer count
   - Color: By segment

### Page 2: Acquisition & Retention

**KPI Cards:**

- New Customers (This Month)
- Customer Retention Rate
- Churn Risk Count
- Avg Customer Lifetime Value

**Visualizations:**

1. New Customer Acquisition Trend (Line Chart)
   - X-axis: Month
   - Y-axis: New customers
   - Color: Two lines (new vs. returning)

2. Retention Curve by Cohort (Line Chart)
   - Multiple lines: One per cohort
   - X-axis: Months active
   - Y-axis: % retained
   - Trend: Show overall average

3. Top Cities by Customer Revenue (Map or Bar)
   - Geographic performance
   - Size: Revenue or customer count
   - Drill-through: City details

4. Purchase Frequency Distribution (Bar Chart)
   - X-axis: Order count ranges
   - Y-axis: Customers
   - Color: Gradient by frequency

---

## 3. PRODUCT DASHBOARD

**Purpose:** Product performance and inventory management  
**Refresh:** Hourly  
**Audience:** Product Manager, Inventory Manager

### Page 1: Product Performance

**KPI Cards:**

- Total Products
- Top Product Revenue
- Dead Stock Count
- Average Product Margin %

**Visualizations:**

1. Product Performance Grid (Matrix)
   - Rows: Top 20 products
   - Columns: Revenue, Units Sold, Profit, Margin %
   - Conditional formatting: Multi-color scale

2. Revenue by Product (Top 15 - Horizontal Bar)
   - Sorting: By revenue desc
   - Color gradient: High=green, Low=red
   - Highlight: Each bar with revenue value

3. Product Price vs. Sales Volume (Scatter)
   - X-axis: Price
   - Y-axis: Units sold
   - Bubble size: Total revenue
   - Color: By category

4. Category Performance Comparison (Small Multiples)
   - 8 small bar charts (one per category)
   - Show: Top 3 products per category
   - Metric: Revenue or Units

### Page 2: Inventory Management

**KPI Cards:**

- Out of Stock Products
- Reorder Alert Count
- Avg Inventory Value
- Turnover Ratio

**Visualizations:**

1. Inventory Status by Category (Stacked Bar)
   - Segments: OK, Caution, Warning, Urgent
   - Color: Green, Yellow, Orange, Red
   - Show: Count of products

2. Stock Level vs. Reorder Level (Scatter)
   - X-axis: Current stock
   - Y-axis: Reorder level
   - Points above line: OK, below: needs action
   - Color: By category

3. Product Velocity (Slow/Fast Movers - Bar)
   - Left side: Fast movers (green)
   - Right side: Slow movers (red)
   - Y-axis: Monthly sales volume

4. Inventory Value by Location (Map or Table)
   - Show warehouse locations
   - Color/size: Inventory value
   - Drill-through: Products in location

---

## 4. OPERATIONAL DASHBOARD

**Purpose:** Daily operations, inventory alerts, fraud monitoring  
**Refresh:** Real-time (5 min)  
**Audience:** Operations Team, Fraud Analyst

### Page 1: Daily Operations

**KPI Cards (Large):**

- Orders Today
- Revenue Today
- Conversion Rate
- Fraud Flag Count

**Visualizations:**

1. Hourly Order Volume (Column Chart)
   - X-axis: Hour of day
   - Y-axis: Order count
   - Baseline: Average
   - Highlight: Current hour

2. Payment Method Distribution (Pie Chart)
   - Show all payment methods
   - Size: Transaction count
   - Highlight: Issue methods in red

3. Reorder Alerts (Priority Table)
   - Columns: Product, Current Stock, Reorder Level, Days to Stockout, Action
   - Sort: By days to stockout ascending
   - Color: Urgent (red), Warning (yellow), OK (green)

### Page 2: Fraud & Risk

**KPI Cards:**

- Fraud Cases (Today)
- Avg Fraud Score
- High-Risk Orders
- Chargeback Count

**Visualizations:**

1. Fraud Risk Score Distribution (Histogram)
   - X-axis: Risk score (0-10)
   - Y-axis: Order count
   - Color: Red (high), Yellow (medium), Green (low)

2. Suspicious Orders (Detail Table)
   - Columns: Order ID, Customer, Amount, Risk Factors, Action
   - Sorting: By risk score desc
   - Highlight: Score > 7 in red

3. Payment Method Risk (Horizontal Bar)
   - X-axis: Fraud %
   - Y-axis: Payment method
   - Threshold line: Average fraud rate

4. Customer Risk Profile (Scatter)
   - X-axis: Days as customer
   - Y-axis: Chargeback/refund count
   - Color: Risk level
   - Size: Lifetime value

---

## CROSS-CUTTING FEATURES

### Drill-Through Capabilities

1. Revenue Card → Revenue by Product
2. Category → Top products in category
3. Product → Customer segments buying product
4. Customer Segment → Individual customer list
5. Cohort → Retention detail by month

### Dynamic Filters (Slicers)

- Date Range (Calendar with preset options)
- Category (Multi-select)
- Payment Method (Multi-select)
- Order Status (Multi-select)
- Customer Segment (Multi-select)
- Price Range (Slider)

### Bookmarks

1. **Executive Summary** - Key metrics focus
2. **Detailed View** - All data visible
3. **YoY Comparison** - Year-over-year view
4. **Forecast View** - Trend lines with forecast

### Row-Level Security (RLS)

- **Executives:** All data
- **Marketing Team:** Customer data only
- **Product Team:** Product & inventory only
- **Finance:** Revenue & payment data only
- **Operations:** Operational & inventory only

---

## DATA CONNECTIONS

### Main Data Source

- **Database:** SQLite (dev) / PostgreSQL (prod)
- **Tables Used:**
  - customers, orders, order_items
  - products, categories, inventory
  - payments, order_statuses
  - Views: MonthlySalesSummary, ProductPerformance, etc.

### Refresh Schedule

- Executive Dashboard: 5 minutes
- Customer Dashboard: Daily 06:00 AM
- Product Dashboard: Hourly
- Operational Dashboard: Real-time (5 min)

### Query Performance

- Pre-aggregate data in database views
- Use materialized tables for complex calculations
- Aggregate at source, not in Power BI
- Limit detail rows to 500K max

---

## DESIGN SPECIFICATIONS

### Color Palette

- **Primary Brand:** #0078D4 (Blue)
- **Success:** #107C10 (Green)
- **Warning:** #FFB900 (Yellow)
- **Error:** #E81123 (Red)
- **Neutral:** #737373 (Gray)

### Typography

- **Title:** Segoe UI, 18pt, Bold
- **Subtitle:** Segoe UI, 14pt, Normal
- **Body:** Segoe UI, 11pt, Normal
- **Data Labels:** Segoe UI, 9pt, Normal

### Layout Principles

- Grid-based layout (6 columns)
- Consistent spacing (20px)
- Mobile-responsive design
- Accessibility: WCAG AA compliant

---

## PERFORMANCE OPTIMIZATION

### Recommendations

1. **Aggregations:** Pre-compute daily totals in database
2. **Incremental Refresh:** New data only (last 7 days)
3. **Composite Models:** Mix import & DirectQuery modes
4. **Query Folding:** Ensure filters pushed to database
5. **Field Metadata:** Add descriptions and formatting

### Load Time Targets

- Dashboard load: < 3 seconds
- Filter response: < 1 second
- Drill-through: < 2 seconds
- Refresh cycle: < 10 minutes (for daily dashboards)

---

## DISTRIBUTION & ACCESS

### Distribution Channels

- **Web:** power.bi.com (embedded)
- **Mobile:** Power BI Mobile App
- **Email:** Subscription exports
- **SharePoint:** Dashboard embeddings

### Scheduling

- **Daily Reports:** 7:00 AM via email
- **Weekly Summary:** Monday 8:00 AM
- **Monthly Executive Report:** 1st of month

### Access Control

- Active Directory / Azure AD
- Role-based permissions
- Department-based filters (RLS)
- Audit logs enabled

---

## KPI DEFINITIONS

### Revenue Metrics

- **Total Revenue:** Sum of all order_items.line_total
- **MoM Growth %:** (This Month - Last Month) / Last Month \* 100
- **YoY Growth %:** (This Year - Last Year) / Last Year \* 100
- **AOV:** Total Revenue / Total Orders

### Customer Metrics

- **New Customers:** Customers with first order in period
- **Active Customers:** Customers with order in last 30 days
- **Retention Rate:** (Customers in month N - Churn) / Customers in month N-1
- **Churn Rate:** Customers inactive > 90 days / Previous active

### Product Metrics

- **Turnover Ratio:** Units Sold / Avg Inventory
- **Margin %:** (Revenue - Cost) / Revenue \* 100
- **Dead Stock:** Products with zero sales in 180 days

---

## TESTING & VALIDATION

### UAT Checklist

- [ ] All visualizations load correctly
- [ ] Filters work as expected
- [ ] Drill-through functionality operational
- [ ] Numbers match source data (+/- rounding)
- [ ] Performance acceptable (< 3 sec)
- [ ] Mobile view responsive
- [ ] Accessibility tested
- [ ] Security and RLS validated

### Deployment Steps

1. Deploy to development workspace
2. UAT validation (2 weeks)
3. Deploy to staging
4. Production smoke testing
5. Announce to stakeholders
6. Final production deployment
7. Monitor for issues (1 week)

---

## MAINTENANCE & SUPPORT

### Review Schedule

- **Weekly:** Check for data anomalies
- **Monthly:** Performance review
- **Quarterly:** Feature enhancement review
- **Annually:** Complete audit & redesign assessment

### Contact

- **BI Team:** bi-support@company.com
- **Slack:** #bi-platform
- **Hours:** 8 AM - 6 PM EST, Mon-Fri

---

_Last Updated: 2026-06-13_  
_Dashboard Version: 1.0 - Initial Release_
