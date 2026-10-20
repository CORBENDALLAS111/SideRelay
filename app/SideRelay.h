#include <stdint.h>
uint64_t relay_start(const char *json);
char *relay_poll(uint64_t session);
void relay_reply(uint64_t session, const char *json);
void relay_cancel(uint64_t session);
void relay_release(uint64_t session);
void relay_string_free(char *string);
