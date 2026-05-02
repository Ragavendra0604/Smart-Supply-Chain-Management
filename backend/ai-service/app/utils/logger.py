import os
import logging
from logging.handlers import RotatingFileHandler

def setup_logger():
    LOG_DIR = os.path.join(os.path.dirname(__file__), "../../../logs")
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)

    log_formatter = logging.Formatter('{"timestamp": "%(asctime)s", "service": "AI_SERVICE", "level": "%(levelname)s", "message": "%(message)s"}')
    log_handler = RotatingFileHandler(os.path.join(LOG_DIR, "ai_service.log"), maxBytes=5*1024*1024, backupCount=2)
    log_handler.setFormatter(log_formatter)

    logger = logging.getLogger("ai_service")
    logger.setLevel(logging.INFO)
    logger.addHandler(log_handler)
    logger.addHandler(logging.StreamHandler())
    return logger

logger = setup_logger()
