(in-package :cl-user)
(defpackage dyna.table
  (:use :cl
        :annot.class
        :dyna.util
        :dyna.structure
        :dyna.column)
  (:import-from :closer-mop
                :validate-superclass
                :standard-direct-slot-definition
                :direct-slot-definition-class
                :class-direct-slots
                :slot-definition-name))
(in-package :dyna.table)

(syntax:use-syntax :annot)

@export
(defclass <dyna-class> () ())

@export
@export-accessors
(defclass <dyna-table-class> (standard-class)
  ((table-name :type (or cons string) :initarg :table-name)
   (dyna :type (or cons dyna) :initarg :dyna :accessor table-dyna)
   (throughput :type (or null cons) :initarg :throughput :accessor table-throughput :initform nil)
   (lsi :type (or null cons) :initarg :lsi :accessor table-lsi :initform nil)
   (gsi :type (or null cons) :initarg :gsi :accessor table-gsi :initform nil)
   (%synced :type boolean :initform nil :accessor table-synced)))

@export
(defun find-the-key-type-key (class type)
  (find type (class-direct-slots class) :key #'key-type :test #'equal))

@export
(defgeneric table-name (table)
  (:method ((table <dyna-table-class>))
    (or (and (slot-boundp table 'table-name)
             (slot-value table 'table-name))
        (format nil "~(~a~)" (class-name table)))))

(defun contains-class-or-subclasses (class target-classes)
  (let ((class (if (typep class 'class)
                   class
                   (find-class class))))
    (find-if (lambda (target-class)
                 (and target-class
                      (or (eq target-class class)
                          (class-inherit-p target-class class))))
             target-classes)))

(defun initialize-around-action (instance initargs)
  (declare (ignore instance))
  (when (getf initargs :dyna)
    (setf (getf initargs :dyna)
          (eval (car (getf initargs :dyna)))))
  (loop for key in '(:table-name :throughput)
        do (when (getf initargs key)
             (setf (getf initargs key)
                   (car (getf initargs key)))))
  (unless (contains-class-or-subclasses (find-class '<dyna-class>) (getf initargs :direct-superclasses))
    (setf (getf initargs :direct-superclasses)
          (cons (find-class '<dyna-class>) (getf initargs :direct-superclasses)))))

(defun initialize-after-action (instance initargs)
  (let ((direct-slots (class-direct-slots instance)))
    (flet ((find-the-name-key (name)
             (find (symbol-name name)
                   direct-slots
                   :key #'(lambda (slot)
                            (symbol-name (slot-definition-name slot)))
                   :test #'equal)))
      (setf (table-lsi instance)
            (when (getf initargs :lsi)
              (mapcar #'(lambda (index) (find-the-name-key index))
                      (getf initargs :lsi))))
      (setf (table-gsi instance)
            (when (getf initargs :gsi)
              (mapcar #'(lambda (list)
                          (setf (getf list :hash)
                                (find-the-name-key (getf list :hash)))
                          (when (getf list :range)
                            (setf (getf list :range)
                                  (find-the-name-key (getf list :range))))
                          list)
                      (getf initargs :gsi))))
      (unless (getf initargs :throughput)
        (setf (table-throughput instance) nil))
      (setf (slot-value instance '%synced) nil))))

(defmethod initialize-instance :around ((instance <dyna-table-class>) &rest initargs)
  (initialize-around-action instance initargs)
  (apply #'call-next-method instance initargs))

(defmethod reinitialize-instance :around ((instance <dyna-table-class>) &rest initargs)
  (initialize-around-action instance initargs)
  (apply #'call-next-method instance initargs))

(defmethod validate-superclass ((class <dyna-table-class>) (super standard-class))
  t)

(defmethod direct-slot-definition-class ((class <dyna-table-class>) &key)
  '<dyna-table-column>)

@export
(defgeneric table-hash-key (class)
  (:method ((class symbol))
    (table-hash-key (find-class class)))

  (:method ((class <dyna-table-class>))
    (find-the-key-type-key class "HASH")))

@export
(defgeneric table-hash-keys (class)
  (:method ((class symbol))
    (table-hash-keys (find-class class)))

  (:method ((class <dyna-table-class>))
    (list* (table-hash-key class)
           (mapcar #'(lambda (gsi)
                       (getf gsi :hash))
                   (table-gsi class)))))

@export
(defgeneric table-range-key (class)
  (:method ((class symbol))
    (table-range-key (find-class class)))
  
  (:method ((class <dyna-table-class>))
    (find-the-key-type-key class "RANGE")))

@export
(defgeneric table-range-keys (class)
  (:method ((class symbol))
    (table-range-keys (find-class class)))

  (:method ((class <dyna-table-class>))
    (cons (table-range-key class)
          (table-lsi class))))

@export
(defun gsi-to-index-name (gsi)
  (gen-gsi-name (append (list (attr-name (getf gsi :hash)))
                        (when (getf gsi :range)
                          (list (attr-name (getf gsi :range)))))))
