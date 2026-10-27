#ifndef BGMORI_ECH_BRIDGE_H
#define BGMORI_ECH_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif
void BgmoriECHBegin(const char *identifier);
void BgmoriECHCancel(const char *identifier);
char *BgmoriECHPerform(const char *identifier, const char *request_json);
void BgmoriECHFree(char *pointer);
char *BgmoriECHInfo(void);
#ifdef __cplusplus
}
#endif
#endif
