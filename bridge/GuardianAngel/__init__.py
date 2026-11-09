from .watchdog import GuardianAngel

def create_instance(c_instance):
    return GuardianAngel(c_instance)
