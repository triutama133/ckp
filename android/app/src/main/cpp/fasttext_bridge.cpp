// Placeholder JNI bridge for fastText integration
#include <jni.h>
#include <string>
#include <vector>
#include <sstream>
#include <unordered_map>
#include <fstream>
#include <algorithm>

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_ckp_1temp_FastTextBridge_stringFromJNI(JNIEnv* env, jobject /* this */) {
    std::string hello = "fastText bridge placeholder";
    return env->NewStringUTF(hello.c_str());
}

static std::unordered_map<std::string, std::vector<std::string>> rules;

static std::vector<std::string> split(const std::string &s, char delim) {
    std::vector<std::string> out;
    std::stringstream ss(s);
    std::string item;
    while (std::getline(ss, item, delim)) {
        if (!item.empty()) out.push_back(item);
    }
    return out;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_ckp_1temp_FastTextBridge_loadRules(JNIEnv* env, jclass cls, jstring jpath) {
    const char* path = env->GetStringUTFChars(jpath, nullptr);
    std::ifstream f(path);
    if (!f.is_open()) {
        env->ReleaseStringUTFChars(jpath, path);
        return;
    }
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty()) continue;
        auto tab = line.find('\t');
        if (tab == std::string::npos) continue;
        std::string label = line.substr(0, tab);
        std::string kws = line.substr(tab + 1);
        auto tokens = split(kws, ',');
        rules[label] = tokens;
    }
    env->ReleaseStringUTFChars(jpath, path);
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_example_ckp_1temp_FastTextBridge_predict(JNIEnv* env, jclass cls, jstring jtext, jint jk) {
    const char* text = env->GetStringUTFChars(jtext, nullptr);
    std::string stext(text);
    env->ReleaseStringUTFChars(jtext, text);
    // naive scoring: count keyword matches per label
    std::unordered_map<std::string,int> score;
    for (auto &kv : rules) score[kv.first] = 0;
    // tokenize simple
    std::vector<std::string> toks;
    std::stringstream ss(stext);
    std::string w;
    while (ss >> w) {
        // normalize basic punctuation
        std::string cleaned;
        for (char c : w) if (std::isalnum((unsigned char)c)) cleaned.push_back(std::tolower(c));
        if (!cleaned.empty()) toks.push_back(cleaned);
    }
    for (auto &kv : rules) {
        for (auto &kw : kv.second) {
            for (auto &t : toks) {
                if (t == kw) score[kv.first] += 1;
            }
        }
    }
    // collect scores into vector and sort
    std::vector<std::pair<std::string,int>> vec;
    for (auto &kv : score) vec.emplace_back(kv.first, kv.second);
    std::sort(vec.begin(), vec.end(), [](auto &a, auto &b){ return a.second > b.second; });
    int k = jk;
    if (k > (int)vec.size()) k = vec.size();
    jobjectArray ret = env->NewObjectArray(k, env->FindClass("java/lang/String"), nullptr);
    for (int i=0;i<k;i++) {
        std::string out = vec[i].first + ":" + std::to_string(vec[i].second);
        env->SetObjectArrayElement(ret, i, env->NewStringUTF(out.c_str()));
    }
    return ret;
}
