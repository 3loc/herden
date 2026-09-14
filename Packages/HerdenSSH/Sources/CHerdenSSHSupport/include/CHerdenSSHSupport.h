#ifndef C_HERDEN_SSH_SUPPORT_H
#define C_HERDEN_SSH_SUPPORT_H

#include <CLibSSH2/libssh2.h>

int herden_libssh2_abandon_session(LIBSSH2_SESSION *session);
void herden_libssh2_prepare_session_abandonment(LIBSSH2_SESSION *session);

typedef ssize_t (*herden_libssh2_receive_callback)(
    libssh2_socket_t socket,
    void *buffer,
    size_t length,
    int flags,
    void **abstract
);

void herden_libssh2_set_receive_callback(
    LIBSSH2_SESSION *session,
    herden_libssh2_receive_callback callback
);

#endif
