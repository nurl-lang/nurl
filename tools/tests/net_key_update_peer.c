/* OpenSSL is an independent peer, never an implementation dependency. */
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static int updates, bad_request;
static void message(int writing, int version, int type, const void *data,
                    size_t len, SSL *ssl, void *arg) {
    (void)version; (void)ssl; (void)arg;
    const unsigned char *p = data;
    if (!writing && type == SSL3_RT_HANDSHAKE && len >= 1 && p[0] == SSL3_MT_KEY_UPDATE) {
        updates++;
        if (len != 5 || p[4] != SSL_KEY_UPDATE_NOT_REQUESTED) bad_request = 1;
    }
}
static int fail(const char *msg) { fprintf(stderr, "%s\n", msg); ERR_print_errors_fp(stderr); return 1; }
int main(int argc, char **argv) {
    if (argc != 7) return 2;
    int fd=atoi(argv[1]), server=atoi(argv[2]), request=atoi(argv[3]);
    SSL_CTX *ctx=SSL_CTX_new(TLS_method());
    if (!ctx) return fail("context");
    SSL_CTX_set_min_proto_version(ctx,TLS1_3_VERSION);
    SSL_CTX_set_max_proto_version(ctx,TLS1_3_VERSION);
    SSL_CTX_set_verify(ctx,SSL_VERIFY_NONE,NULL);
    SSL_CTX_set_msg_callback(ctx,message);
    if (!SSL_CTX_set_ciphersuites(ctx,argv[6])) return fail("cipher");
    if (server && (!SSL_CTX_use_certificate_file(ctx,argv[4],SSL_FILETYPE_PEM)
                   || !SSL_CTX_use_PrivateKey_file(ctx,argv[5],SSL_FILETYPE_PEM))) return fail("identity");
    SSL *ssl=SSL_new(ctx);
    SSL_set_fd(ssl,fd);
    if ((server ? SSL_accept(ssl) : SSL_connect(ssl)) != 1) return fail("handshake");
    unsigned char payload[32768], echo[32768];
    for (int round=0;round<4;round++) {
        memset(payload,'A'+round,sizeof(payload));
        if (!SSL_key_update(ssl,request) || SSL_do_handshake(ssl)!=1) return fail("key update");
        if (SSL_write(ssl,payload,sizeof(payload)) != sizeof(payload)) return fail("write");
        int n=0;
        while (n < sizeof(echo)) {
            int got=SSL_read(ssl,echo+n,sizeof(echo)-n);
            if (got<=0) return fail("read");
            n+=got;
        }
        if (memcmp(payload,echo,sizeof(payload))) return fail("echo mismatch");
        if (bad_request || updates != (request ? round+1 : 0)) return fail("missing or incorrect KeyUpdate response");
    }
    SSL_shutdown(ssl);
    SSL_free(ssl); SSL_CTX_free(ctx); close(fd);
    return 0;
}
