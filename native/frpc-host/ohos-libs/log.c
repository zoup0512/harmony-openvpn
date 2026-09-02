// Minimal android/log shim for the GOOS=android Go runtime on OHOS.
// The runtime only links these symbols for crash reporting; route them to
// stderr so child-process output stays visible in hilog.
#include <stdarg.h>
#include <stdio.h>

int __android_log_print(int prio, const char *tag, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[go:%s] ", tag != NULL ? tag : "?");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    return 0;
}

int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap)
{
    fprintf(stderr, "[go:%s] ", tag != NULL ? tag : "?");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    return 0;
}

int __android_log_write(int prio, const char *tag, const char *text)
{
    fprintf(stderr, "[go:%s] %s\n", tag != NULL ? tag : "?", text != NULL ? text : "");
    return 0;
}

int __android_log_buf_write(int bufID, int prio, const char *tag, const char *text)
{
    return __android_log_write(prio, tag, text);
}

int __android_log_buf_print(int bufID, int prio, const char *tag, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int rc = __android_log_vprint(prio, tag, fmt, ap);
    va_end(ap);
    return rc;
}
