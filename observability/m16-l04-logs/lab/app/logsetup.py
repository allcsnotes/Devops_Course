"""Structured logging for the allcsvideos lab services (M16-L04).
One JSON object per line on stdout. Every line carries the service, the instance and the request_id of the request
being handled. A redaction filter masks secrets and personal data before anything is written."""
import contextvars, json, logging, os, re, socket, sys, time

request_id = contextvars.ContextVar("request_id", default="-")
SERVICE = os.environ.get("SERVICE", "api")
INSTANCE = socket.gethostname()

SECRET_KEYS = {"password", "token", "authorization", "card_number", "cvv", "otp"}
EMAIL = re.compile(r"\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[a-z]{2,})\b")
BEARER = re.compile(r"(Bearer\s+)[A-Za-z0-9._-]+")


def mask(value):
    if isinstance(value, dict):
        return {k: "[REDACTED]" if k.lower() in SECRET_KEYS else mask(v) for k, v in value.items()}
    if isinstance(value, str):
        return BEARER.sub(r"\1[REDACTED]", EMAIL.sub(r"\1***@\2", value))
    return value


class ContextFilter(logging.Filter):
    """Adds the current request_id to every record, however deep in the code it was logged."""
    def filter(self, record):
        record.request_id = request_id.get()
        return True


class RedactFilter(logging.Filter):
    """Masks secret fields and e-mail addresses in the message and in every extra field."""
    def filter(self, record):
        record.msg = mask(str(record.msg))
        for k, v in list(record.__dict__.get("fields", {}).items()):
            record.fields[k] = "[REDACTED]" if k.lower() in SECRET_KEYS else mask(v)
        return True


class JsonFormatter(logging.Formatter):
    def format(self, r):
        doc = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(r.created)) + f".{int(r.msecs):03d}Z",
               "level": r.levelname.lower(), "service": SERVICE, "instance": INSTANCE,
               "request_id": r.request_id, "msg": r.getMessage(), **getattr(r, "fields", {})}
        if r.exc_info:
            doc["exc"] = self.formatException(r.exc_info)   # the whole stack trace stays inside ONE line
        return json.dumps(doc, ensure_ascii=False)


class TextFormatter(logging.Formatter):
    """The unstructured way: a sentence with values glued in. Stack traces span many lines."""
    def format(self, r):
        r.message = r.getMessage() + "".join(f" {k}={v}" for k, v in getattr(r, "fields", {}).items())
        line = f"{self.formatTime(r)} {r.levelname} [{SERVICE}] {r.message}"
        if r.exc_info:
            line += "\n" + self.formatException(r.exc_info)
        return line


def setup():
    h = logging.StreamHandler(sys.stdout)
    h.addFilter(ContextFilter())
    if os.environ.get("REDACT", "1") == "1":
        h.addFilter(RedactFilter())
    if os.environ.get("LOG_FORMAT", "json") == "text":   # the old way, for comparison
        h.setFormatter(TextFormatter())
    else:
        h.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [h]
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
    return logging.getLogger(SERVICE)
