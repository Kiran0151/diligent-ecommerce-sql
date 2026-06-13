"""
ETL Pipeline for E-Commerce Analytics Platform
Extracts data from CSV, validates, transforms, and loads into SQLite
Features: Data quality checks, error handling, logging, schema validation
"""

import pandas as pd
import sqlite3
import logging
from pathlib import Path
from datetime import datetime
import sys
import json
from typing import Dict, List, Tuple, Optional
import re
import numpy as np

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('etl_pipeline.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuration
class Config:
    DATA_DIR = Path(__file__).parent / 'data'
    DB_PATH = Path(__file__).parent / 'ecom.db'
    LOG_DIR = Path(__file__).parent / 'logs'
    
    # Data validation rules
    VALIDATION_RULES = {
        'customers': {
            'customer_id': {'type': 'int', 'nullable': False, 'unique': True},
            'name': {'type': 'str', 'nullable': False, 'min_length': 2},
            'email': {'type': 'str', 'nullable': False, 'pattern': r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'},
            'phone': {'type': 'str', 'nullable': True},
            'city': {'type': 'str', 'nullable': False}
        },
        'products': {
            'product_id': {'type': 'int', 'nullable': False, 'unique': True},
            'product_name': {'type': 'str', 'nullable': False},
            'category': {'type': 'str', 'nullable': False},
            'price': {'type': 'float', 'nullable': False, 'min': 0.01}
        },
        'orders': {
            'order_id': {'type': 'int', 'nullable': False, 'unique': True},
            'customer_id': {'type': 'int', 'nullable': False},
            'order_date': {'type': 'date', 'nullable': False},
            'order_status': {'type': 'str', 'nullable': False}
        }
    }


class DataValidator:
    """Validates data quality and integrity"""
    
    def __init__(self):
        self.errors = []
        self.warnings = []
    
    def validate_dataframe(self, df: pd.DataFrame, table_name: str) -> Tuple[bool, Dict]:
        """Validate dataframe against schema rules"""
        logger.info(f"Validating {table_name} - {len(df)} rows")
        
        if table_name not in Config.VALIDATION_RULES:
            logger.warning(f"No validation rules for {table_name}")
            return True, {'rows': len(df), 'errors': 0}
        
        rules = Config.VALIDATION_RULES[table_name]
        errors_count = 0
        warnings_count = 0
        
        for column, rule in rules.items():
            if column not in df.columns:
                self.errors.append(f"{table_name}: Missing column '{column}'")
                errors_count += 1
                continue
            
            # Check nullability
            if not rule.get('nullable', True):
                null_count = df[column].isna().sum()
                if null_count > 0:
                    msg = f"{table_name}.{column}: {null_count} null values (not allowed)"
                    self.errors.append(msg)
                    errors_count += 1
            
            # Check data type
            if not df[column].isna().all():  # Only if not all null
                if rule['type'] == 'int':
                    if not all(df[column].dropna().apply(lambda x: isinstance(x, (int, np.integer)))):
                        self.warnings.append(f"{table_name}.{column}: Non-integer values found, attempting conversion")
                        try:
                            df[column] = pd.to_numeric(df[column], errors='coerce')
                            warnings_count += 1
                        except:
                            self.errors.append(f"{table_name}.{column}: Cannot convert to integer")
                            errors_count += 1
                
                elif rule['type'] == 'float':
                    try:
                        df[column] = pd.to_numeric(df[column], errors='coerce')
                    except:
                        self.errors.append(f"{table_name}.{column}: Cannot convert to float")
                        errors_count += 1
            
            # Check min value
            if 'min' in rule and not df[column].isna().all():
                min_val = df[column].min()
                if min_val < rule['min']:
                    msg = f"{table_name}.{column}: Values below minimum ({min_val} < {rule['min']})"
                    self.warnings.append(msg)
                    warnings_count += 1
            
            # Check pattern (regex)
            if 'pattern' in rule and not df[column].isna().all():
                pattern = rule['pattern']
                invalid = df[~df[column].str.match(pattern, na=False)]
                if len(invalid) > 0:
                    msg = f"{table_name}.{column}: {len(invalid)} values don't match pattern"
                    self.warnings.append(msg)
                    warnings_count += 1
        
        is_valid = errors_count == 0
        return is_valid, {
            'rows': len(df),
            'errors': errors_count,
            'warnings': warnings_count,
            'error_messages': self.errors[-5:] if self.errors else []
        }
    
    def check_referential_integrity(self, data_dict: Dict[str, pd.DataFrame]) -> Dict:
        """Check foreign key relationships"""
        logger.info("Checking referential integrity...")
        integrity_issues = {}
        
        # Check customer_id in orders
        if 'orders' in data_dict and 'customers' in data_dict:
            valid_customer_ids = set(data_dict['customers']['customer_id'].unique())
            invalid_orders = data_dict['orders'][~data_dict['orders']['customer_id'].isin(valid_customer_ids)]
            if len(invalid_orders) > 0:
                integrity_issues['orphaned_orders'] = len(invalid_orders)
                logger.warning(f"Found {len(invalid_orders)} orders with invalid customer_id")
        
        # Check product_id in order_items
        if 'order_items' in data_dict and 'products' in data_dict:
            valid_product_ids = set(data_dict['products']['product_id'].unique())
            invalid_items = data_dict['order_items'][~data_dict['order_items']['product_id'].isin(valid_product_ids)]
            if len(invalid_items) > 0:
                integrity_issues['orphaned_order_items'] = len(invalid_items)
                logger.warning(f"Found {len(invalid_items)} order_items with invalid product_id")
        
        return integrity_issues


class DataTransformer:
    """Transforms data into target schema"""
    
    @staticmethod
    def transform_customers(df: pd.DataFrame) -> pd.DataFrame:
        """Transform customer data"""
        logger.info("Transforming customers data...")
        
        df = df.copy()
        
        # Split name into first and last name if needed
        if 'name' in df.columns and 'first_name' not in df.columns:
            name_split = df['name'].str.split(n=1, expand=True)
            df['first_name'] = name_split[0]
            df['last_name'] = name_split[1] if len(name_split.columns) > 1 else 'Unknown'
        
        # Add default columns
        df['country'] = df.get('country', 'USA')
        df['is_active'] = 1
        df['created_date'] = datetime.now()
        df['last_updated'] = datetime.now()
        
        # Rename if necessary
        df = df.rename(columns={'customer_id': 'customer_id'})
        
        return df[['customer_id', 'first_name', 'last_name', 'email', 'phone', 'city', 'country', 'is_active', 'created_date', 'last_updated']]
    
    @staticmethod
    def transform_products(df: pd.DataFrame) -> pd.DataFrame:
        """Transform product data"""
        logger.info("Transforming products data...")
        
        df = df.copy()
        
        # Add default columns
        df['sku'] = 'SKU-' + df['product_id'].astype(str).str.zfill(5)
        df['cost'] = df['price'] * 0.6  # Estimate cost as 60% of price
        df['is_active'] = 1
        df['created_date'] = datetime.now()
        df['last_updated'] = datetime.now()
        
        # Add category_id mapping
        categories = {
            'Electronics': 1, 'Home': 2, 'Clothing': 3, 'Sports': 4,
            'Toys': 5, 'Books': 6, 'Beauty': 7, 'Grocery': 8
        }
        df['category_id'] = df['category'].map(categories)
        
        return df[['product_id', 'product_name', 'category_id', 'price', 'cost', 'sku', 'is_active', 'created_date', 'last_updated']]
    
    @staticmethod
    def transform_orders(df: pd.DataFrame) -> pd.DataFrame:
        """Transform order data"""
        logger.info("Transforming orders data...")
        
        df = df.copy()
        
        # Map status to ID
        status_map = {
            'pending': 1, 'processing': 2, 'shipped': 3,
            'delivered': 4, 'cancelled': 5
        }
        df['status_id'] = df['order_status'].map(status_map)
        
        # Add default columns
        df['discount_amount'] = 0
        df['tax_amount'] = 0
        df['shipping_cost'] = 0
        df['created_date'] = datetime.now()
        df['last_updated'] = datetime.now()
        
        return df[['order_id', 'customer_id', 'order_date', 'status_id', 'total_amount', 'discount_amount', 'tax_amount', 'shipping_cost', 'created_date', 'last_updated']]
    
    @staticmethod
    def transform_order_items(df: pd.DataFrame) -> pd.DataFrame:
        """Transform order items data"""
        logger.info("Transforming order_items data...")
        
        df = df.copy()
        
        # Calculate line total
        df['line_total'] = df['quantity'] * df['unit_price']
        
        # Add default columns
        df['discount_percent'] = 0
        df['created_date'] = datetime.now()
        
        return df[['item_id', 'order_id', 'product_id', 'quantity', 'unit_price', 'line_total', 'discount_percent', 'created_date']]
    
    @staticmethod
    def transform_payments(df: pd.DataFrame) -> pd.DataFrame:
        """Transform payment data"""
        logger.info("Transforming payments data...")
        
        df = df.copy()
        
        # Map payment methods to ID
        method_map = {
            'credit_card': 1, 'debit_card': 2, 'paypal': 3,
            'bank_transfer': 4, 'apple_pay': 5, 'google_pay': 6, 'gift_card': 7
        }
        df['payment_method_id'] = df['payment_method'].map(method_map)
        
        # Add default columns
        df['transaction_id'] = 'TXN-' + df['payment_id'].astype(str)
        df['is_refunded'] = 0
        df['created_date'] = datetime.now()
        
        return df[['payment_id', 'order_id', 'payment_method_id', 'amount', 'payment_date', 'transaction_id', 'is_refunded', 'created_date']]


class ETLPipeline:
    """Main ETL orchestration"""
    
    def __init__(self, db_path: Path = Config.DB_PATH):
        self.db_path = db_path
        self.validator = DataValidator()
        self.transformer = DataTransformer()
        self.data = {}
        self.stats = {}
    
    def extract(self) -> bool:
        """Extract data from CSV files"""
        logger.info(f"Starting extraction from {Config.DATA_DIR}...")
        
        csv_files = {
            'customers': Config.DATA_DIR / 'customers.csv',
            'products': Config.DATA_DIR / 'products.csv',
            'orders': Config.DATA_DIR / 'orders.csv',
            'order_items': Config.DATA_DIR / 'order_items.csv',
            'payments': Config.DATA_DIR / 'payments.csv'
        }
        
        for table_name, filepath in csv_files.items():
            try:
                if not filepath.exists():
                    logger.error(f"File not found: {filepath}")
                    return False
                
                df = pd.read_csv(filepath)
                logger.info(f"Extracted {table_name}: {len(df)} rows, {len(df.columns)} columns")
                self.data[table_name] = df
                self.stats[f'{table_name}_extracted'] = len(df)
            
            except Exception as e:
                logger.error(f"Error extracting {table_name}: {str(e)}")
                return False
        
        return True
    
    def validate(self) -> bool:
        """Validate extracted data"""
        logger.info("Starting validation...")
        
        all_valid = True
        for table_name, df in self.data.items():
            is_valid, validation_stats = self.validator.validate_dataframe(df, table_name)
            if not is_valid:
                all_valid = False
                logger.error(f"Validation failed for {table_name}")
                logger.error(f"Details: {validation_stats}")
        
        # Check referential integrity
        integrity_issues = self.validator.check_referential_integrity(self.data)
        if integrity_issues:
            logger.warning(f"Referential integrity issues: {integrity_issues}")
        
        return all_valid
    
    def transform(self) -> bool:
        """Transform data to target schema"""
        logger.info("Starting transformation...")
        
        try:
            self.data['customers'] = self.transformer.transform_customers(self.data['customers'])
            self.data['products'] = self.transformer.transform_products(self.data['products'])
            self.data['orders'] = self.transformer.transform_orders(self.data['orders'])
            self.data['order_items'] = self.transformer.transform_order_items(self.data['order_items'])
            self.data['payments'] = self.transformer.transform_payments(self.data['payments'])
            logger.info("Transformation completed successfully")
            return True
        
        except Exception as e:
            logger.error(f"Transformation failed: {str(e)}")
            return False
    
    def load(self) -> bool:
        """Load data into SQLite database"""
        logger.info(f"Starting load to {self.db_path}...")
        
        try:
            # Remove old database
            if self.db_path.exists():
                self.db_path.unlink()
                logger.info("Removed existing database")
            
            # Create connection
            conn = sqlite3.connect(self.db_path)
            
            # Load data (order matters due to foreign keys)
            load_order = ['customers', 'categories', 'products', 'inventory', 'orders', 'order_items', 'payments']
            
            # Create dimension tables first
            self._create_dimension_tables(conn)
            
            # Load fact tables
            for table_name in load_order:
                if table_name in self.data:
                    self.data[table_name].to_sql(table_name, conn, if_exists='append', index=False)
                    row_count = len(self.data[table_name])
                    logger.info(f"Loaded {table_name}: {row_count} rows")
                    self.stats[f'{table_name}_loaded'] = row_count
            
            # Create indexes
            self._create_indexes(conn)
            
            conn.commit()
            conn.close()
            logger.info("Load completed successfully")
            return True
        
        except Exception as e:
            logger.error(f"Load failed: {str(e)}")
            return False
    
    def _create_dimension_tables(self, conn: sqlite3.Connection):
        """Create dimension tables"""
        cursor = conn.cursor()
        
        # Create categories
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS categories (
                category_id INTEGER PRIMARY KEY,
                category_name TEXT NOT NULL UNIQUE,
                description TEXT,
                created_date TIMESTAMP
            )
        ''')
        
        categories = [
            (1, 'Electronics', 'Electronic devices and gadgets'),
            (2, 'Home', 'Home and garden products'),
            (3, 'Clothing', 'Apparel and fashion items'),
            (4, 'Sports', 'Sports and outdoor equipment'),
            (5, 'Toys', 'Toys and games'),
            (6, 'Books', 'Books and publications'),
            (7, 'Beauty', 'Beauty and personal care'),
            (8, 'Grocery', 'Food and grocery items')
        ]
        
        cursor.executemany('INSERT OR IGNORE INTO categories VALUES (?, ?, ?, ?)', 
                          [(c[0], c[1], c[2], datetime.now()) for c in categories])
        
        # Similar for other dimension tables...
        conn.commit()
    
    def _create_indexes(self, conn: sqlite3.Connection):
        """Create database indexes"""
        cursor = conn.cursor()
        
        indexes = [
            'CREATE INDEX IF NOT EXISTS idx_customer_email ON customers(email)',
            'CREATE INDEX IF NOT EXISTS idx_product_category ON products(category_id)',
            'CREATE INDEX IF NOT EXISTS idx_order_customer ON orders(customer_id)',
            'CREATE INDEX IF NOT EXISTS idx_order_date ON orders(order_date)',
            'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)',
            'CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id)',
            'CREATE INDEX IF NOT EXISTS idx_payment_order ON payments(order_id)',
        ]
        
        for index in indexes:
            cursor.execute(index)
        
        conn.commit()
        logger.info("Indexes created")
    
    def run(self) -> Dict:
        """Execute complete ETL pipeline"""
        logger.info("=" * 60)
        logger.info("Starting E-Commerce ETL Pipeline")
        logger.info("=" * 60)
        
        pipeline_success = (
            self.extract() and
            self.validate() and
            self.transform() and
            self.load()
        )
        
        logger.info("=" * 60)
        if pipeline_success:
            logger.info("✅ ETL Pipeline Completed Successfully")
        else:
            logger.error("❌ ETL Pipeline Failed")
        logger.info("=" * 60)
        
        return {
            'success': pipeline_success,
            'statistics': self.stats,
            'errors': self.validator.errors,
            'warnings': self.validator.warnings
        }


def main():
    """Main entry point"""
    pipeline = ETLPipeline()
    result = pipeline.run()
    
    # Print summary
    print("\n" + "=" * 60)
    print("ETL Pipeline Summary")
    print("=" * 60)
    print(f"Status: {'✅ Success' if result['success'] else '❌ Failed'}")
    print(f"\nStatistics:")
    for key, value in result['statistics'].items():
        print(f"  {key}: {value}")
    
    if result['errors']:
        print(f"\nErrors ({len(result['errors'])}):")
        for error in result['errors'][:5]:
            print(f"  - {error}")
    
    if result['warnings']:
        print(f"\nWarnings ({len(result['warnings'])}):")
        for warning in result['warnings'][:5]:
            print(f"  - {warning}")
    
    print("=" * 60)
    sys.exit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()
