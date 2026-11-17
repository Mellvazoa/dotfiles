#include "pam_check.h"
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int pam_conv_func(int num_msg, const struct pam_message **msg,
                         struct pam_response **resp, void *appdata_ptr) {
    if (num_msg <= 0 || !resp || !appdata_ptr) return PAM_CONV_ERR;
    *resp = calloc(num_msg, sizeof(struct pam_response));
    if (!*resp) return PAM_BUF_ERR;
    for (int i = 0; i < num_msg; ++i) {
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF || msg[i]->msg_style == PAM_PROMPT_ECHO_ON) {
            (*resp)[i].resp = strdup((char *)appdata_ptr);
            (*resp)[i].resp_retcode = 0;
        }
    }
    return PAM_SUCCESS;
}

int pam_verify(const char *user, const char *password) {
    if (!user || !password) return 0;
    struct pam_conv conv = { pam_conv_func, (void *)password };
    pam_handle_t *pamh = NULL;
    int retval = pam_start("screensaver", user, &conv, &pamh);
    if (retval != PAM_SUCCESS) return 0;
    retval = pam_authenticate(pamh, 0);
    pam_end(pamh, retval);
    return (retval == PAM_SUCCESS);
}
