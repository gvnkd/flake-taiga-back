from settings.common import *

DEBUG = True

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'taiga',
        'USER': '',
        'PASSWORD': '',
        'HOST': '',
        'PORT': '',
    }
}

EVENTS_PUSH_BACKEND = "taiga.events.backends.rabbitmq.EventsPushBackend"
EVENTS_PUSH_BACKEND_OPTIONS = {
    "url": "amqp://localhost:5672"
}

CELERY_ENABLED = False

MEDIA_ROOT = ""
STATIC_ROOT = ""

WEBHOOKS_ENABLED = False
ENABLE_TELEMETRY = False
PUBLIC_REGISTER_ENABLED = True
