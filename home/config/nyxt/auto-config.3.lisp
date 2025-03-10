(define-configuration browser
  ((theme theme:+dark-theme+)))

(define-configuration (web-buffer)
  ((default-modes (pushnew 'nyxt/mode/style:dark-mode %slot-value%))))

(defmethod customize-instance ((browser browser) &key)
  (setf (slot-value browser 'restore-session-on-startup-p) nil)
  (setf (slot-value browser 'default-cookie-policy) :accept))

(define-configuration (web-buffer)
  ((default-modes
    (remove-if (lambda (nyxt::m) (string= (symbol-name nyxt::m) "DARK-MODE"))
               %slot-value%))))

(define-configuration browser
  ((theme theme:+light-theme+)))

(define-configuration browser
  ((theme theme:+dark-theme+)))

(define-configuration browser
  ((theme theme:+light-theme+)))

(define-configuration browser
  ((theme theme:+dark-theme+)))

(define-configuration browser
  ((theme theme:+light-theme+)))
