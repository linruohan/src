/*	$OpenBSD: file.h,v 1.10 2001/03/01 20:54:35 provos Exp $	*/
/*	$NetBSD: file.h,v 1.11 1995/03/26 20:24:13 jtc Exp $	*/

/*
 * Copyright (c) 1982, 1986, 1989, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the University of
 *	California, Berkeley and its contributors.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *	@(#)file.h	8.2 (Berkeley) 8/20/94
 */

#include <sys/fcntl.h>
#include <sys/unistd.h>

#ifdef _KERNEL
#include <sys/queue.h>

struct proc;
struct uio;
struct knote;

/*
 * Kernel descriptor table.
 * One entry for each open kernel vnode and socket.
 */
struct file {
	LIST_ENTRY(file) f_list;/* list of active files */
	short	f_flag;		/* see fcntl.h */
#define	DTYPE_VNODE	1	/* file */
#define	DTYPE_SOCKET	2	/* communications endpoint */
#define	DTYPE_PIPE	3	/* pipe */
#define	DTYPE_KQUEUE	4	/* event queue */
	short	f_type;		/* descriptor type */
	long	f_count;	/* reference count */
	long	f_msgcount;	/* references from message queue */
	struct	ucred *f_cred;	/* credentials associated with descriptor */
	struct	fileops {
		int	(*fo_read)	__P((struct file *fp, off_t *, 
					     struct uio *uio,
					     struct ucred *cred));
		int	(*fo_write)	__P((struct file *fp, off_t *,
					     struct uio *uio,
					     struct ucred *cred));
		int	(*fo_ioctl)	__P((struct file *fp, u_long com,
					    caddr_t data, struct proc *p));
		int	(*fo_select)	__P((struct file *fp, int which,
					    struct proc *p));
		int	(*fo_kqfilter)	__P((struct file *fp,
					    struct knote *kn));
		int	(*fo_close)	__P((struct file *fp, struct proc *p));
	} *f_ops;
	off_t	f_offset;
	caddr_t	f_data;		/* vnode or socket */
};

LIST_HEAD(filelist, file);
extern struct filelist filehead;	/* head of list of open files */
extern int maxfiles;			/* kernel limit on number of open files */
extern int nfiles;			/* actual number of open files */
extern struct fileops vnops;		/* vnode operations for files */

int     dofileread __P((struct proc *, int, struct file *, void *, size_t,
            off_t *, register_t *));
int     dofilewrite __P((struct proc *, int, struct file *, const void *,
            size_t, off_t *, register_t *));

#endif /* _KERNEL */
