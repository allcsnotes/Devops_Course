package com.allcs.catalog;

import java.io.Serializable;

// one row of the courses table; Serializable so the list can be cached in Redis
record Course(String id, String title, int priceEur, int seatsLeft) implements Serializable {}
