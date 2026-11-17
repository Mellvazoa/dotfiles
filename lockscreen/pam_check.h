#ifndef PAM_CHECK_H
#define PAM_CHECK_H

#ifdef __cplusplus
extern "C" {
#endif

int pam_verify(const char *user, const char *password);

#ifdef __cplusplus
}
#endif

#endif
