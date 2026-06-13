"""
RFM Segmentation & Cohort Analysis Module
Calculates RFM scores and generates customer segments for targeting
"""

import pandas as pd
import sqlite3
from pathlib import Path
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)

class RFMAnalysis:
    """RFM (Recency, Frequency, Monetary) analysis and segmentation"""
    
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row
    
    def calculate_rfm(self) -> pd.DataFrame:
        """Calculate RFM scores and segments"""
        
        # Get customer metrics
        query = """
        WITH customer_metrics AS (
            SELECT 
                c.customer_id,
                ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as recency,
                COUNT(DISTINCT o.order_id) as frequency,
                ROUND(SUM(oi.line_total), 2) as monetary
            FROM customers c
            LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status_id IN (3, 4)
            LEFT JOIN order_items oi ON o.order_id = oi.order_id
            GROUP BY c.customer_id
        )
        SELECT *,
               NTILE(5) OVER (ORDER BY recency ASC) as r_score,
               NTILE(5) OVER (ORDER BY frequency DESC) as f_score,
               NTILE(5) OVER (ORDER BY monetary DESC) as m_score
        FROM customer_metrics
        """
        
        df = pd.read_sql_query(query, self.conn)
        
        # Segment customers
        df['segment'] = df.apply(self._segment_customer, axis=1)
        
        return df
    
    def _segment_customer(self, row):
        """Classify customer into segment"""
        r, f, m = row['r_score'], row['f_score'], row['m_score']
        
        if r >= 4 and f >= 4 and m >= 4:
            return '👑 Champion'
        elif r >= 4 and f >= 3 and m >= 3:
            return '⭐ Loyal'
        elif r >= 3 and f >= 3 and m >= 2:
            return '🌟 Potential'
        elif r >= 4 and f <= 2:
            return '🆕 New'
        elif r <= 2 and f >= 3 and m >= 3:
            return '⚠️ At Risk'
        else:
            return '❌ Lost'
    
    def get_segment_metrics(self) -> pd.DataFrame:
        """Get summary metrics by segment"""
        rfm_df = self.calculate_rfm()
        
        return rfm_df.groupby('segment').agg({
            'customer_id': 'count',
            'recency': 'mean',
            'frequency': 'mean',
            'monetary': ['sum', 'mean']
        }).round(2)


class CohortAnalysis:
    """Monthly cohort analysis and retention tracking"""
    
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
    
    def generate_retention_matrix(self) -> pd.DataFrame:
        """Generate cohort retention matrix"""
        
        query = """
        WITH cohorts AS (
            SELECT 
                c.customer_id,
                STRFTIME('%Y-%m', MIN(o.order_date)) as cohort_month,
                STRFTIME('%Y-%m', o.order_date) as order_month,
                ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY o.order_date) as order_num
            FROM customers c
            JOIN orders o ON c.customer_id = o.customer_id
            WHERE o.status_id IN (3, 4)
        )
        SELECT 
            cohort_month,
            order_month,
            ROUND((JULIANDAY(order_month) - JULIANDAY(cohort_month))/30.0, 0) as months_since_first,
            COUNT(DISTINCT customer_id) as customers
        FROM cohorts
        GROUP BY cohort_month, months_since_first
        ORDER BY cohort_month, months_since_first
        """
        
        df = pd.read_sql_query(query, self.conn)
        
        # Pivot to create matrix
        pivot_df = df.pivot_table(
            index='cohort_month',
            columns='months_since_first',
            values='customers',
            aggfunc='sum'
        )
        
        return pivot_df
    
    def get_cohort_revenue(self) -> pd.DataFrame:
        """Get revenue by cohort over time"""
        
        query = """
        WITH cohort_data AS (
            SELECT 
                c.customer_id,
                STRFTIME('%Y-%m', MIN(o.order_date)) as cohort_month,
                STRFTIME('%Y-%m', o.order_date) as order_month,
                SUM(oi.line_total) as revenue
            FROM customers c
            JOIN orders o ON c.customer_id = o.customer_id
            JOIN order_items oi ON o.order_id = oi.order_id
            WHERE o.status_id IN (3, 4)
            GROUP BY c.customer_id, order_month
        )
        SELECT 
            cohort_month,
            ROUND((JULIANDAY(order_month) - JULIANDAY(cohort_month))/30.0, 0) as months_since_first,
            SUM(revenue) as cohort_revenue
        FROM cohort_data
        GROUP BY cohort_month, months_since_first
        ORDER BY cohort_month, months_since_first
        """
        
        return pd.read_sql_query(query, self.conn)


def export_rfm_segments(db_path: Path, output_csv: Path):
    """Export RFM segments to CSV for marketing campaigns"""
    rfm = RFMAnalysis(db_path)
    df = rfm.calculate_rfm()
    df.to_csv(output_csv, index=False)
    logger.info(f"RFM segments exported to {output_csv}")


def export_cohort_analysis(db_path: Path, output_csv: Path):
    """Export cohort analysis to CSV"""
    cohort = CohortAnalysis(db_path)
    df = cohort.generate_retention_matrix()
    df.to_csv(output_csv)
    logger.info(f"Cohort analysis exported to {output_csv}")


if __name__ == '__main__':
    db_path = Path(__file__).parent.parent / 'ecom.db'
    
    # Run RFM analysis
    rfm = RFMAnalysis(db_path)
    print("\n=== RFM Segmentation ===")
    segments = rfm.get_segment_metrics()
    print(segments)
    
    # Run cohort analysis
    cohort = CohortAnalysis(db_path)
    print("\n=== Retention Matrix ===")
    retention = cohort.generate_retention_matrix()
    print(retention)
    
    # Export results
    export_rfm_segments(db_path, Path(__file__).parent.parent / 'output' / 'rfm_segments.csv')
    export_cohort_analysis(db_path, Path(__file__).parent.parent / 'output' / 'cohort_analysis.csv')
