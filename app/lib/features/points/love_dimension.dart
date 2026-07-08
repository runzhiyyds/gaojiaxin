enum LoveDimension {
  care,
  companionship,
  understanding,
  growth,
  responsibility,
  ritual,
  passion;

  String get label {
    switch (this) {
      case LoveDimension.care:
        return '关心';
      case LoveDimension.companionship:
        return '陪伴';
      case LoveDimension.understanding:
        return '理解';
      case LoveDimension.growth:
        return '成长';
      case LoveDimension.responsibility:
        return '责任';
      case LoveDimension.ritual:
        return '仪式感';
      case LoveDimension.passion:
        return '激情';
    }
  }

  String get dbValue => name;

  static LoveDimension? fromDb(String? value) {
    if (value == null) return null;
    switch (value) {
      case 'care':
        return LoveDimension.care;
      case 'companionship':
        return LoveDimension.companionship;
      case 'understanding':
        return LoveDimension.understanding;
      case 'growth':
        return LoveDimension.growth;
      case 'responsibility':
        return LoveDimension.responsibility;
      case 'ritual':
        return LoveDimension.ritual;
      case 'passion':
        return LoveDimension.passion;
      default:
        return null;
    }
  }
}

