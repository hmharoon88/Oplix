const FEATURE_SECTIONS = [
  {
    "title": "Executive Dashboard",
    "items": [
      "Real-time sales dashboard",
      "Daily sales summary",
      "Weekly/monthly/yearly trends",
      "Profit dashboard",
      "Gross margin dashboard",
      "Net profit dashboard",
      "Multi-store overview",
      "Store ranking",
      "KPI dashboard",
      "Custom widgets",
      "Drill-down analytics",
      "Mobile dashboard access",
      "Role-based dashboards",
      "Owner/manager dashboards"
    ]
  },
  {
    "title": "Sales & Revenue",
    "items": [
      "Total sales tracking",
      "Fuel sales",
      "In-store sales",
      "Lottery sales",
      "Tobacco sales",
      "Vape sales",
      "Alcohol sales",
      "Food service sales",
      "Coffee sales",
      "Car wash sales",
      "ATM revenue tracking",
      "Money order sales",
      "EBT sales tracking",
      "Cash vs card reporting",
      "Hourly sales analytics",
      "Peak hours analysis",
      "Department-wise sales",
      "Product-wise sales",
      "SKU-level analytics",
      "Refund tracking",
      "Void transaction tracking",
      "Discount tracking",
      "Coupon tracking",
      "Promotion analytics",
      "Tax reporting",
      "Shift reconciliation",
      "Register balancing",
      "Daily cash reconciliation"
    ]
  },
  {
    "title": "Fuel",
    "items": [
      "Fuel inventory monitoring",
      "Tank level monitoring",
      "Fuel deliveries",
      "Fuel variance reports",
      "Fuel shrinkage analysis",
      "Fuel price management",
      "Competitor fuel pricing",
      "Fuel margin analytics",
      "Pump uptime tracking",
      "Pump maintenance tracking",
      "Fuel dispenser inspections",
      "Fuel spill incident logs",
      "Fuel compliance checklists",
      "DEF tracking",
      "Car wash integration"
    ]
  },
  {
    "title": "Inventory",
    "items": [
      "Real-time inventory",
      "Barcode scanning",
      "SKU management",
      "Category management",
      "Vendor-linked inventory",
      "Inventory receiving",
      "Purchase orders",
      "Invoice matching",
      "Stock transfers",
      "Dead stock reports",
      "Overstock alerts",
      "Low-stock alerts",
      "Auto reorder suggestions",
      "Inventory forecasting",
      "Expiration tracking",
      "Product recalls",
      "Product rotation tracking",
      "Cigarette inventory",
      "Lottery inventory",
      "Beer/alcohol inventory",
      "Cooler inventory",
      "Warehouse inventory",
      "Inventory shrinkage reports",
      "Theft/loss tracking"
    ]
  },
  {
    "title": "Vendors",
    "items": [
      "Vendor database",
      "Vendor contact management",
      "Vendor contracts",
      "Vendor performance tracking",
      "Vendor invoices",
      "Invoice approval workflow",
      "Delivery schedules",
      "Purchase order management",
      "Outstanding balances",
      "Credit terms tracking",
      "Price comparison reports",
      "Vendor communication logs",
      "Service vendor tracking",
      "Repair vendor tracking",
      "Fuel supplier tracking",
      "Distributor tracking"
    ]
  },
  {
    "title": "Expenses",
    "items": [
      "Utility expense tracking",
      "Payroll expenses",
      "Rent tracking",
      "Fuel purchase expenses",
      "Repair expenses",
      "Maintenance costs",
      "Vendor payments",
      "Insurance tracking",
      "Tax expense tracking",
      "Credit card fee tracking",
      "Bank fee tracking",
      "Marketing expenses",
      "Miscellaneous expenses",
      "Recurring expense tracking",
      "Expense categorization",
      "Expense approvals",
      "Receipt uploads",
      "Receipt OCR scanning",
      "Budgeting tools",
      "Forecasting tools"
    ]
  },
  {
    "title": "Accounting & Financials",
    "items": [
      "Profit & loss statements",
      "Balance sheet",
      "Cash flow reporting",
      "Accounts payable",
      "Accounts receivable",
      "Daily deposits",
      "Bank reconciliation",
      "Sales tax reporting",
      "Payroll integration",
      "QuickBooks integration",
      "Xero integration",
      "Multi-location accounting",
      "Audit trails",
      "Financial exports",
      "CPA/accountant access"
    ]
  },
  {
    "title": "Employees",
    "items": [
      "Employee database",
      "Shift scheduling",
      "Time clock",
      "Attendance tracking",
      "Overtime tracking",
      "PTO tracking",
      "Payroll integration",
      "Employee roles/permissions",
      "Performance tracking",
      "Training tracking",
      "Certification tracking",
      "Employee messaging",
      "Task assignments",
      "Incident reports",
      "Disciplinary logs"
    ]
  },
  {
    "title": "Operations",
    "items": [
      "Opening checklists",
      "Closing checklists",
      "Shift handoff logs",
      "Daily task lists",
      "Recurring tasks",
      "SOP management",
      "Digital SOPs",
      "Task verification photos",
      "QR code workflows",
      "Store walk-throughs",
      "Bathroom inspections",
      "Cooler inspections",
      "Coffee station checks",
      "Cleaning logs",
      "Trash removal tracking",
      "Parking lot inspections",
      "Safety inspections",
      "Compliance inspections"
    ]
  },
  {
    "title": "Maintenance",
    "items": [
      "Work orders",
      "Preventive maintenance",
      "Corrective maintenance",
      "Equipment database",
      "Asset lifecycle tracking",
      "HVAC maintenance",
      "Refrigeration maintenance",
      "Coffee machine maintenance",
      "Ice machine maintenance",
      "Fuel pump maintenance",
      "Lottery machine maintenance",
      "POS hardware maintenance",
      "Plumbing tickets",
      "Electrical tickets",
      "Repair approvals",
      "Maintenance vendors",
      "Service history",
      "Maintenance scheduling"
    ]
  },
  {
    "title": "Compliance & Audits",
    "items": [
      "Tobacco compliance",
      "Alcohol compliance",
      "FDA compliance",
      "OSHA compliance",
      "Food safety compliance",
      "Fire safety inspections",
      "Emergency exit checks",
      "Health inspection prep",
      "Age verification audits",
      "Incident reporting",
      "Injury reporting",
      "Security incident logs",
      "Digital audit forms",
      "Corrective action tracking",
      "Compliance scoring"
    ]
  },
  {
    "title": "Food Service",
    "items": [
      "Food prep tracking",
      "Temperature logging",
      "Hot holding logs",
      "Cooler/freezer temperatures",
      "HACCP logs",
      "Expiration checks",
      "Food waste tracking",
      "Recipe management",
      "Grab-and-go inventory",
      "Coffee station management",
      "Fountain drink maintenance",
      "Kitchen cleaning logs"
    ]
  },
  {
    "title": "Lottery",
    "items": [
      "Lottery sales tracking",
      "Scratch-off inventory",
      "Lottery reconciliation",
      "Lottery settlement reports",
      "Lottery activation tracking",
      "Lottery terminal monitoring",
      "Lottery cash balancing",
      "Lottery shortage reporting"
    ]
  },
  {
    "title": "Security & Loss Prevention",
    "items": [
      "CCTV integration",
      "Incident reports",
      "Theft reporting",
      "Refund abuse tracking",
      "Void abuse tracking",
      "Cash shortage tracking",
      "Employee exception reporting",
      "Alarm logs",
      "Panic button integration",
      "Access logs"
    ]
  },
  {
    "title": "Multi-Store",
    "items": [
      "Chain-wide dashboards",
      "District manager view",
      "Regional reporting",
      "Cross-store analytics",
      "Benchmarking",
      "Store comparisons",
      "Centralized SOP deployment",
      "Chain-wide announcements",
      "Multi-store maintenance tracking",
      "Enterprise permissions"
    ]
  },
  {
    "title": "Communication System",
    "items": [
      "Team messaging",
      "Group chat",
      "Store announcements",
      "Emergency alerts",
      "Task notifications",
      "Read receipts",
      "File sharing",
      "Photo/video uploads",
      "Email/SMS integrations"
    ]
  },
  {
    "title": "Reporting & Analytics",
    "items": [
      "Sales trends",
      "Margin analysis",
      "Expense trends",
      "Labor analytics",
      "Vendor analytics",
      "Inventory analytics",
      "Fuel analytics",
      "Audit reports",
      "Maintenance reports",
      "Custom reports",
      "Scheduled reports",
      "PDF exports",
      "Excel exports",
      "AI-generated insights"
    ]
  },
  {
    "title": "AI & Automation",
    "items": [
      "AI-generated SOPs",
      "AI anomaly detection",
      "Predictive inventory",
      "Predictive maintenance",
      "Smart alerts",
      "Automated reminders",
      "Automated recurring tasks",
      "AI sales forecasting",
      "AI labor forecasting"
    ]
  },
  {
    "title": "Mobile Features",
    "items": [
      "Mobile apps",
      "Offline mode",
      "Push notifications",
      "QR scanning",
      "Barcode scanning",
      "Geolocation tracking",
      "Camera/photo verification",
      "Mobile approvals"
    ]
  },
  {
    "title": "Integrations",
    "items": [
      "POS integrations",
      "Accounting integrations",
      "Fuel management systems",
      "Payroll systems",
      "Banking integrations",
      "Lottery systems",
      "Security systems",
      "IoT sensors",
      "Temperature sensors",
      "Email/SMS integrations",
      "Firebase integration",
      "API access"
    ]
  }
];
