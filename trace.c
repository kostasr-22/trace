#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/ptrace.h>
#include <sys/errno.h>
#include <sys/wait.h>
#include <sys/user.h>

void detach_and_exit(int exit_status);
void handle_signals(int signum);

unsigned int instcount = 0;
pid_t pid;

void detach_and_exit(int exit_status) {

	int retval;

	retval = ptrace(PTRACE_DETACH, pid, NULL, NULL);

	if (retval == 0) {
		goto exit;
	}

#if 0
	if (errno == ESRCH) {

		/* Try stopping the process first */
		retval = kill(pid, SIGSTOP);

		if (retval != 0) {
			exit_status = EXIT_FAILURE;
			perror("KILL");
			goto exit;
		}

		/* Wait for process to stop */
		wait(NULL);

		/* Try to detach again now that process is stopped */
		retval = ptrace(PTRACE_DETACH, pid, NULL, NULL);

		if (retval != 0) {
			perror("PTRACE_DETACH");
		}

	} else {
		perror("PTRACE_DETACH");
	}
#endif
		perror("PTRACE_DETACH");
exit:

	printf("Process executed %u instructions\n", instcount);

	exit(exit_status);
}

void handle_signals(int signum) {

	if (signum != SIGINT) {
		fprintf(stderr, "Unhandled signal received: %d\n", signum);
		detach_and_exit(EXIT_FAILURE);
	}

	detach_and_exit(0);
}

int main(int argc, char **argv) {

	FILE *dumpfile;
	struct user_regs_struct regs;
	struct sigaction act;
   pid_t wpid;
	int status, retval;

	/* Handle command line arguments */

	if (argc < 2) {
		fprintf(stderr, "Usage: %s <pid>\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	pid = atoi(argv[1]);


	/* Setup signal handler */

	act.sa_handler = handle_signals;

	retval = sigaction(SIGINT, &act, NULL);

	if (retval != 0) {
		perror("SIGACTION");
		exit(EXIT_FAILURE);
	}


	/* Attach to the process to be traced */

	retval = ptrace(PTRACE_ATTACH, pid, NULL, NULL);
	
	if (retval != 0) {
		perror("PTRACE_ATTACH");
		exit(EXIT_FAILURE);
	}

	/* Open the dump file for output */

	dumpfile = fopen("trace.dump", "w");

	if (dumpfile == NULL) {
		perror("FOPEN");
		detach_and_exit(EXIT_FAILURE);
	}


	/* Single step through the process dumping the value in the EIP register
	 * at each step.
	 */

	while (1) {

		/* Wait for process to stop */

		wpid = waitpid(pid, &status, __WALL);

      if (wpid == -1)
      {
         perror("wait");
         break;
      }

      if (wpid != pid)
      {
         printf("Uhhh... we wanted to wait for %d but got %d\n", pid, wpid);
         break;
      }

		if (WIFEXITED(status)) {
			printf("Process terminated\n");
			break;
		}

		/* Read registers */

		retval = ptrace(PTRACE_GETREGS, pid, NULL, &regs);

		if (retval != 0) {
			perror("PTRACE_GETREGS");
			detach_and_exit(EXIT_FAILURE);
		}

		/* Record value of instruction pointer */

#ifdef __x86_64__
		fprintf(dumpfile, "%lx\n", regs.rip);
#else
		fprintf(dumpfile, "%lx\n", regs.eip);
#endif
		instcount++;

		/* Advance execution to next instruction */

		retval = ptrace(PTRACE_SINGLESTEP, pid, NULL, NULL);

		if (retval != 0) {
			perror("PTRACE_SINGLESTEP");
			detach_and_exit(EXIT_FAILURE);
		}

	}

	fclose(dumpfile);
	printf("Process executed %u instructions\n", instcount);

	return 0;
}
