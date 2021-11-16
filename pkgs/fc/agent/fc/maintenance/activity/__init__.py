"""Base class for maintenance activities."""
from enum import Enum


class RebootType(Enum):
    WARM = 1
    COLD = 2


class Activity:
    """Maintenance activity which is executed as request payload.

    Activities are executed possibly several times until they succeed or
    exceeed their retry limit. Individual maintenance activities should
    subclass this class and add custom behaviour to its methods.

    Attributes: `stdout`, `stderr` capture the outcomes of shellouts.
    `returncode` controls the resulting request state. If `duration` is
    set, it overrules execution timing done by the calling scope. Use
    this if a logical transaction spans several attempts, e.g. for
    reboots.
    """

    stdout = None
    stderr = None
    returncode = None
    duration = None
    request = None  # backpointer, will be set in Request
    reboot_needed = None

    def __init__(self):
        """Creates activity object (add args if you like).

        Note that this method gets only called once and the value of
        __dict__ is serialized using PyYAML between runs.
        """
        pass

    def __getstate__(self):
        state = self.__dict__.copy()
        # Deserializing loggers breaks, remove them before serializing (to YAML).
        if "log" in state:
            del state["log"]
        return state

    def set_up_logging(self, log):
        self.log = log

    def run(self):
        """Executes maintenance activity.

        Execution takes place in a request-specific directory as CWD. Do
        whatever you want here, but do not destruct `request.yaml`.
        Directory contents is preserved between several attempts.

        This method is expected to update self.stdout, self.stderr, and
        self.returncode after each run. Request state is determined
        according to the EXIT_* constants in `state.py`. Any returncode
        not listed there means hard failure and causes the request to be
        archived. Uncaught exceptions are handled the same way.
        """
        self.returncode = 0

    def load(self):
        """Loads external state.

        This method gets called every time the Activity object is
        deserialized to perform additional state updating. This should
        be rarely needed, as the contents of self.__dict__ is preserved
        anyway. CWD is set to the request dir.
        """
        pass

    def dump(self):
        """Saves additional state during serialization."""
        pass
