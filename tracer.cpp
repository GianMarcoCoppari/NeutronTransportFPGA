#include <cstdio>
#include <dlfcn.h>
#include <cxxabi.h>
#include <unistd.h>
#include <fcntl.h>
#include <memory>
#include <string>
#include <cstring>
#include <mutex> // Necessario per gestire i thread di OpenMC

#define notrace __attribute__((no_instrument_function))

// --- CONFIGURAZIONE ---
static const std::string triggerfunc{"openmc_run"}; 

// --- VARIABILI GLOBALI STATICHE ---
// Il file descriptor rimane aperto tra le chiamate
static int log_fd = -1; 
static bool activetrace = false;
// Il mutex impedisce a due thread di scrivere contemporaneamente
static std::mutex log_mutex; 

extern "C" {
    
    notrace std::string demangle(const char* name) {
        if (name == nullptr) return "-- unknown --";
        int status = -1;
        std::unique_ptr<char, void(*)(void*)> res{
            abi::__cxa_demangle(name, nullptr, nullptr, &status), std::free
        };
        return (status == 0) ? res.get() : name;
    }

    // Variabile thread-local per evitare ricorsione interna
    static thread_local bool tracing_internal_guard = false;

    void notrace __cyg_profile_func_enter(void *this_fn, void *call_site) {
        if (tracing_internal_guard) return;
        tracing_internal_guard = true;

        Dl_info info;
        if (dladdr(this_fn, &info) && info.dli_sname) {
            std::string name = demangle(info.dli_sname);

            // --- SEZIONE CRITICA (Thread Safe) ---
            // Blocchiamo gli altri thread mentre decidiamo se scrivere
            std::lock_guard<std::mutex> lock(log_mutex);

            // 1. Logica di ATTIVAZIONE (Trigger)
            if (!activetrace) {
                if (name.find(triggerfunc) != std::string::npos) {
                    activetrace = true;
                    // APRIAMO IL FILE UNA SOLA VOLTA QUI
                    if (log_fd == -1) {
                        // O_TRUNC pulisce il file vecchio all'avvio del trigger
                        log_fd = open("tracinglog.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
                        if (log_fd != -1) {
                            dprintf(log_fd, "=== START TRACING TRIGGERED BY: %s ===\n", name.c_str());
                        }
                    }
                }
            }

            // 2. Scrittura veloce (solo se attivo e file aperto)
            if (activetrace && log_fd != -1) {
                // Usiamo dprintf che è efficiente
                dprintf(log_fd, "[ENTER] %s\n", name.c_str());
            }
        } 
        
        tracing_internal_guard = false;
    }

    void notrace __cyg_profile_func_exit(void *this_fn, void *call_site) {
        if (tracing_internal_guard) return;
        
        // Controllo preliminare per evitare locking inutile se non stiamo tracciando
        if (!activetrace) return;

        tracing_internal_guard = true;
        
        Dl_info info;
        if (dladdr(this_fn, &info) && info.dli_sname) {
            std::string name = demangle(info.dli_sname);

            // --- SEZIONE CRITICA ---
            std::lock_guard<std::mutex> lock(log_mutex);

            // Controlliamo di nuovo activetrace dentro il lock per sicurezza
            if (activetrace && log_fd != -1) {
                
                // Se vuoi loggare l'uscita, decommenta:
                // dprintf(log_fd, "[EXIT ] %s\n", name.c_str());

                // 3. Logica di DISATTIVAZIONE
                if (name.find(triggerfunc) != std::string::npos) {
                    dprintf(log_fd, "=== STOP TRACING (Exited Trigger) ===\n");
                    
                    // CHIUDIAMO IL FILE QUI
                    close(log_fd);
                    log_fd = -1; // Resettiamo il descriptor
                    activetrace = false;
                }
            }
        }
        tracing_internal_guard = false;
    }
}